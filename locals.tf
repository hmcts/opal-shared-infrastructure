locals {
  db_port      = 5432
  db_version   = 17
  db_collation = "en_GB.utf8"
  default_envs = ["demo", "ithc", "perftest", "test", "stg"]

  legacy_postgresql_default_server_configuration = [
    {
      name  = "backslash_quote"
      value = "on"
    }
  ]

  legacy_postgresql_fdw_server_configuration = [
    {
      name  = "azure.extensions"
      value = "POSTGRES_FDW"
    },
    {
      name  = "azure.enable_temp_tablespaces_on_local_ssd"
      value = "off"
    }
  ]

  legacy_postgresql_all_servers = {
    "fines-service" = {
      component     = "fines-service"
      db_name       = "opal-fines-db"
      enabled_envs  = local.default_envs
      collation     = local.db_collation
      pgsql_version = local.db_version
      pgsql_databases = concat(
        [
          {
            name = "opal-fines-db"
          }
        ],
        var.env == "stg" ? [
          # gctest currently exists with en_US.utf8 collation while the
          # fines-service server module uses en_GB.utf8 for its databases.
          # The upstream module exposes collation per module/server rather
          # than per database, so adopting gctest here would force a database
          # replacement. Leave it unmanaged until the module supports per-DB
          # collation or the database can safely be normalised.
          {
            name = "test-gob-fines-db"
          },
          {
            name = "test-opal-fines-db"
          }
        ] : []
      )
      pgsql_server_configuration = local.legacy_postgresql_fdw_server_configuration
    }

    "user-service" = {
      component                  = "user-service"
      db_name                    = "opal-user-db"
      enabled_envs               = local.default_envs
      collation                  = local.db_collation
      pgsql_version              = local.db_version
      pgsql_databases            = [{ name = "opal-user-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }

    "file-handling-service" = {
      component                  = "file-handling-service"
      db_name                    = "opal-file-handling-db"
      enabled_envs               = local.default_envs
      collation                  = local.db_collation
      pgsql_version              = local.db_version
      pgsql_databases            = [{ name = "opal-file-handling-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }

    "logging-service" = {
      component                  = "logging-service"
      db_name                    = "opal-logging-db"
      enabled_envs               = local.default_envs
      collation                  = local.db_collation
      pgsql_version              = local.db_version
      pgsql_databases            = [{ name = "opal-logging-db" }]
      pgsql_server_configuration = local.legacy_postgresql_fdw_server_configuration
    }

    "log-audit-service" = {
      component                  = "log-audit-service"
      db_name                    = "opal-log-audit-db"
      enabled_envs               = ["stg"]
      collation                  = local.db_collation
      pgsql_version              = local.db_version
      pgsql_databases            = [{ name = "opal-log-audit-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }

    "maintenance-service" = {
      component       = "maintenance-service"
      db_name         = "opal-maintenance-db"
      enabled_envs    = ["demo", "stg"]
      collation       = local.db_collation
      pgsql_version   = local.db_version
      pgsql_databases = [{ name = "opal-maintenance-db" }]
      pgsql_server_configuration = [
        {
          name  = "backslash_quote"
          value = "safe_encoding"
        }
      ]
    }

    "print-service" = {
      component                  = "print-service"
      db_name                    = "opal-print-db"
      enabled_envs               = ["stg"]
      collation                  = local.db_collation
      pgsql_version              = local.db_version
      pgsql_databases            = [{ name = "opal-print-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }
  }

  consolidated_postgresql_enabled = contains(["demo", "ithc"], var.env)

  consolidated_postgresql_databases = {
    for _, v in local.legacy_postgresql_all_servers :
    upper(replace(replace(replace(v.db_name, "opal-", ""), "-db", ""), "-", "_")) => {
      component = v.component
      db_name   = v.db_name
    }
  }

  postgresql_all_enabed_servers_none_consolidated = {
    for name, config in local.legacy_postgresql_all_servers :
    name => config
    if !local.consolidated_postgresql_enabled && contains(config.enabled_envs, var.env)
  }

  consolidated_postgresql_server_configuration = [
    {
      name  = "azure.enable_temp_tablespaces_on_local_ssd"
      value = "off"
    },
    {
      name  = "azure.extensions"
      value = "PG_STAT_STATEMENTS"
    },
    {
      name  = "logfiles.download_enable"
      value = "ON"
    },
    {
      name  = "logfiles.retention_days"
      value = "7"
    }
  ]
}
