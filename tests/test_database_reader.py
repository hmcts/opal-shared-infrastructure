import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('reader', Path(__file__).parents[1] / 'bin/configure_database_reader.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
ROLE = 'DTS JIT Access opal DB Reader NonProd'
OID = '11111111-1111-1111-1111-111111111111'


class ReaderTests(unittest.TestCase):
    def environment(self):
        return dict(PGHOST='example.postgres.database.azure.com', PGUSER='jenkins-test-mi',
                    OPAL_DB_OWNER='pgadmin', OPAL_READER_NAME=ROLE, OPAL_READER_ID=OID,
                    OPAL_DATABASES=json.dumps(['opal-test', 'opal-test']))

    def test_token_confined_to_psql_environment(self):
        marker = 'unit-test-placeholder-not-a-credential'
        calls = []
        def run(args, **kwargs):
            calls.append((args, kwargs))
            return subprocess.CompletedProcess(args, 0, json.dumps({'accessToken': marker}) if args[0] == 'az' else '', '')
        output = io.StringIO()
        with patch.dict(os.environ, self.environment(), clear=True), patch.object(reader.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(output):
            reader.main()
        self.assertEqual(len(calls), 3)  # token, server role, one deduplicated database
        self.assertNotIn(marker, output.getvalue())
        for args, kwargs in calls:
            self.assertNotIn(marker, repr(args))
            self.assertNotIn(marker, kwargs.get('input', ''))
            if args[0] == 'psql':
                self.assertEqual(kwargs['env']['PGPASSWORD'], marker)
                self.assertIn('--set=ON_ERROR_STOP=1', args)
                self.assertEqual(kwargs['env']['PGSSLMODE'], 'require')

    def test_sql_failure_stops_remaining_databases(self):
        count = []
        def run(args, **kwargs):
            count.append(args[0])
            if args[0] == 'az':
                return subprocess.CompletedProcess(args, 0, '{"accessToken":"test-placeholder"}', '')
            return subprocess.CompletedProcess(args, 1, '', 'raw output must not be copied')
        with patch.dict(os.environ, self.environment(), clear=True), patch.object(reader.subprocess, 'run', side_effect=run):
            with self.assertRaisesRegex(RuntimeError, 'SQL failed for postgres') as error:
                reader.main()
        self.assertNotIn('raw output', str(error.exception))
        self.assertEqual(count, ['az', 'psql'])

    def test_invalid_inputs_do_not_authenticate(self):
        env = self.environment()
        env['OPAL_READER_NAME'] = "bad'; DROP ROLE pgadmin; --"
        with patch.dict(os.environ, env, clear=True), patch.object(reader.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                reader.main()
            run.assert_not_called()


@unittest.skipUnless(os.environ.get('OPAL_PG_INTEGRATION') == '1', 'isolated PostgreSQL service only')
class PostgresTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('PGHOST') != 'localhost':
            raise RuntimeError('Integration tests must only target the isolated localhost service')
        cls.env = dict(os.environ, PGDATABASE='postgres', PGUSER='postgres', PGSSLMODE='disable')
        cls.sql('''
CREATE ROLE pgadmin LOGIN;
CREATE DATABASE "opal-reader-test" OWNER pgadmin;
CREATE TABLE public.entra_role_fixture (role_name text, object_id text);
CREATE FUNCTION pg_catalog.pgaadauth_create_principal_with_oid(text,text,text,boolean,boolean)
RETURNS text LANGUAGE plpgsql AS $f$
BEGIN
 EXECUTE format('CREATE ROLE %I LOGIN', $1);
 INSERT INTO public.entra_role_fixture VALUES ($1,$2);
 RETURN 'created';
END $f$;
CREATE FUNCTION pg_catalog.pgaadauth_list_principals(boolean)
RETURNS TABLE(rolename name, principaltype text, objectid text, tenantid text, ismfa integer, isadmin integer)
LANGUAGE sql AS $f$ SELECT role_name::name, 'group'::text, object_id, 'tenant'::text, 0, 0 FROM public.entra_role_fixture $f$;
''')
        cls.sql('SET ROLE pgadmin; CREATE TABLE public.before_grant(id integer); INSERT INTO public.before_grant VALUES (1);', 'opal-reader-test')

    @classmethod
    def sql(cls, query, database='postgres', expected=0):
        result = subprocess.run(['psql','-X','--no-password','--set=ON_ERROR_STOP=1','--tuples-only','--no-align','--file=-'],
                                input=query, text=True, env=dict(cls.env, PGDATABASE=database), capture_output=True)
        if (result.returncode == 0) != (expected == 0):
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    def test_replay_future_tables_denied_writes_and_conflicting_mapping(self):
        # Two complete reconciliations against a real PostgreSQL server.
        for _ in range(2):
            reader.run_psql(self.env, 'postgres', reader.principal_sql(ROLE, OID))
            reader.run_psql(self.env, 'opal-reader-test', reader.grants_sql(ROLE, 'pgadmin', 'opal-reader-test'))
        count = self.sql('SELECT count(*) FROM public.entra_role_fixture;')
        self.assertEqual(count, '1')
        self.sql('SET ROLE pgadmin; CREATE TABLE public.after_grant(id integer); INSERT INTO public.after_grant VALUES (2);', 'opal-reader-test')
        set_role = 'SET ROLE ' + reader.identifier(ROLE) + '; '
        for table in ['before_grant', 'after_grant']:
            self.sql(set_role + 'SELECT * FROM public.' + table, 'opal-reader-test')
            self.sql(set_role + 'INSERT INTO public.' + table + ' VALUES (3)', 'opal-reader-test', expected=1)
            self.sql(set_role + 'UPDATE public.' + table + ' SET id=3', 'opal-reader-test', expected=1)
            self.sql(set_role + 'DELETE FROM public.' + table, 'opal-reader-test', expected=1)
        self.sql(set_role + 'CREATE TABLE public.denied(id integer)', 'opal-reader-test', expected=1)
        with self.assertRaises(RuntimeError):
            reader.run_psql(self.env, 'postgres', reader.principal_sql(ROLE, '22222222-2222-2222-2222-222222222222'))
        self.assertEqual(self.sql('SELECT count(*) FROM public.entra_role_fixture;'), '1')


if __name__ == '__main__':
    unittest.main()
