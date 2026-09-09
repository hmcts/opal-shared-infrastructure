#!/usr/bin/env python3
"""Apply OPAL-owned reader grants using the pipeline's existing managed identity.

No credentials in arguments, files or logs. Azure CLI output stays in memory;
psql receives its token only through a private child-process environment.
"""
import json
import os
import re
import subprocess
import sys
import uuid


def checked_name(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._():-]*", value):
        raise ValueError("Invalid database, role or identity name")
    return value


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def identifier(value):
    return '"' + value.replace('"', '""') + '"'


def principal_sql(reader, object_id):
    role = literal(checked_name(reader))
    oid = literal(str(uuid.UUID(object_id)))
    return f"""BEGIN;
-- Every invocation locks in postgres, including concurrent/retried applies.
SELECT pg_advisory_xact_lock(hashtext('opal-reader:' || {role}));
DO $opal$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = {role}) THEN
    PERFORM pg_catalog.pgaadauth_create_principal_with_oid({role}, {oid}, 'group', false, false);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pgaadauth_list_principals(false)
      AS principal(role_name, principal_type, object_id, tenant_id, is_mfa, is_admin)
    WHERE role_name = {role} AND lower(object_id::text) = {oid}
      AND lower(principal_type::text) = 'group' AND lower(is_admin::text) IN ('0', 'false', 'f')
  ) THEN
    RAISE EXCEPTION 'Existing OPAL reader role does not match the intended non-admin Entra group';
  END IF;
END
$opal$;
COMMIT;
"""


def grants_sql(reader, owner, database):
    role = identifier(checked_name(reader))
    owner_role = identifier(checked_name(owner))
    db = identifier(checked_name(database))
    # The application's configured login owns Flyway-created objects. SET ROLE
    # uses the existing module-granted membership; no ownership/admin changes.
    return f"""BEGIN;
SET ROLE {owner_role};
GRANT CONNECT ON DATABASE {db} TO {role};
GRANT USAGE ON SCHEMA public TO {role};
GRANT SELECT ON ALL TABLES IN SCHEMA public TO {role};
ALTER DEFAULT PRIVILEGES FOR ROLE {owner_role} IN SCHEMA public GRANT SELECT ON TABLES TO {role};
COMMIT;
"""


def run_psql(environment, database, sql):
    child_env = dict(environment, PGDATABASE=database)
    result = subprocess.run(
        ["psql", "-X", "--no-password", "--set=ON_ERROR_STOP=1", "--file=-"],
        input=sql, text=True, env=child_env, capture_output=True, timeout=180,
    )
    if result.returncode:
        # Never copy raw subprocess output (which may contain connection data).
        raise RuntimeError(f"Reader grant SQL failed for {database} (exit {result.returncode}); no success recorded")


def main():
    reader = checked_name(os.environ["OPAL_READER_NAME"])
    owner = checked_name(os.environ["OPAL_DB_OWNER"])
    user = checked_name(os.environ["PGUSER"])
    object_id = str(uuid.UUID(os.environ["OPAL_READER_ID"]))
    databases = json.loads(os.environ["OPAL_DATABASES"])
    if not isinstance(databases, list) or not databases:
        raise ValueError("OPAL_DATABASES must be a non-empty JSON list")
    databases = sorted({checked_name(name) for name in databases})
    if not os.environ.get("PGHOST"):
        raise ValueError("PGHOST is required")

    # Reuse the Jenkins Azure CLI login, tenant, subscription and config directory.
    # A new authentication flow or a switch of Azure account is not performed.
    result = subprocess.run(
        ["az", "account", "get-access-token", "--resource-type", "oss-rdbms", "--output", "json"],
        text=True, capture_output=True, timeout=60,
    )
    if result.returncode:
        raise RuntimeError("Unable to obtain the pipeline identity's PostgreSQL token")
    token = json.loads(result.stdout)["accessToken"]
    if not isinstance(token, str) or not token:
        raise RuntimeError("Azure CLI returned no PostgreSQL token")
    environment = dict(os.environ, PGUSER=user, PGPASSWORD=token,
                       PGPORT="5432", PGSSLMODE="require", PGCONNECT_TIMEOUT="30")
    run_psql(environment, "postgres", principal_sql(reader, object_id))
    for database in databases:
        run_psql(environment, database, grants_sql(reader, owner, database))
    print(f"OPAL reader grants reconciled for {len(databases)} database(s)")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, RuntimeError, subprocess.TimeoutExpired, OSError) as error:
        # Do not print arbitrary exception text or child output containing secrets.
        if isinstance(error, RuntimeError):
            print(str(error), file=sys.stderr)
        else:
            print("OPAL reader configuration failed: check inputs, identity, connectivity and dependencies", file=sys.stderr)
        sys.exit(1)
