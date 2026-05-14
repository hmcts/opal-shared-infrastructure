locals {
  db_fines_name        = "psql-${var.product}-fines-db"
  db_user_name         = "psql-${var.product}-user-db"
  db_maintenance_name  = "psql-${var.product}-maintenance-db"
  db_logging_name      = "${var.product}-logging-db"
  db_log_audit_name    = "${var.product}-log-audit-db"
  db_file_handler_name = "${var.product}-file-db"
  db_port              = 5432

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
      enabled_envs  = ["demo", "ithc", "perftest", "test", "stg"]
      collation     = null
      pgsql_version = "15"
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
      enabled_envs               = ["demo", "ithc", "perftest", "test", "stg"]
      collation                  = "en_US.utf8"
      pgsql_version              = "16"
      pgsql_databases            = [{ name = "opal-user-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }

    "logging-service" = {
      component                  = "logging-service"
      db_name                    = "opal-logging-db"
      enabled_envs               = ["stg"]
      collation                  = null
      pgsql_version              = "15"
      pgsql_databases            = [{ name = "opal-logging-db" }]
      pgsql_server_configuration = local.legacy_postgresql_fdw_server_configuration
    }

    "log-audit-service" = {
      component                  = "log-audit-service"
      db_name                    = "opal-log-audit-db"
      enabled_envs               = ["stg"]
      collation                  = null
      pgsql_version              = "15"
      pgsql_databases            = [{ name = "opal-log-audit-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }

    "file-handler" = {
      component                  = "file-handler"
      db_name                    = "opal-file-db"
      enabled_envs               = ["demo", "perftest", "test", "stg"]
      collation                  = "en_US.utf8"
      pgsql_version              = "16"
      pgsql_databases            = [{ name = "opal-file-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }

    "maintenance-service" = {
      component                  = "maintenance-service"
      db_name                    = "opal-maintenance-db"
      enabled_envs               = ["demo", "stg"]
      collation                  = "en_US.utf8"
      pgsql_version              = "16"
      pgsql_databases            = [{ name = "opal-maintenance-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }

    "print-service" = {
      component                  = "print-service"
      db_name                    = "opal-print-db"
      enabled_envs               = ["stg"]
      collation                  = null
      pgsql_version              = "15"
      pgsql_databases            = [{ name = "opal-print-db" }]
      pgsql_server_configuration = local.legacy_postgresql_default_server_configuration
    }
  }

  legacy_postgresql_server_ids_by_env = {
    demo = {
      "fines-service"       = "/subscriptions/c68a4bed-4c3d-4956-af51-4ae164c1957c/resourceGroups/opal-fines-service-data-demo/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-fines-service-demo"
      "user-service"        = "/subscriptions/c68a4bed-4c3d-4956-af51-4ae164c1957c/resourceGroups/opal-user-service-data-demo/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-user-service-demo"
      "file-handler"        = "/subscriptions/c68a4bed-4c3d-4956-af51-4ae164c1957c/resourceGroups/opal-file-handler-data-demo/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-file-handler-demo"
      "maintenance-service" = "/subscriptions/c68a4bed-4c3d-4956-af51-4ae164c1957c/resourceGroups/opal-maintenance-service-data-demo/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-maintenance-service-demo"
    }
    ithc = {
      "fines-service" = "/subscriptions/ba71a911-e0d6-4776-a1a6-079af1df7139/resourceGroups/opal-fines-service-data-ithc/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-fines-service-ithc"
      "user-service"  = "/subscriptions/ba71a911-e0d6-4776-a1a6-079af1df7139/resourceGroups/opal-user-service-data-ithc/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-user-service-ithc"
    }
    perftest = {
      "fines-service" = "/subscriptions/3eec5bde-7feb-4566-bfb6-805df6e10b90/resourceGroups/opal-fines-service-data-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-fines-service-test"
      "user-service"  = "/subscriptions/3eec5bde-7feb-4566-bfb6-805df6e10b90/resourceGroups/opal-user-service-data-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-user-service-test"
      "file-handler"  = "/subscriptions/3eec5bde-7feb-4566-bfb6-805df6e10b90/resourceGroups/opal-file-handler-data-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-file-handler-test"
    }
    test = {
      "fines-service" = "/subscriptions/3eec5bde-7feb-4566-bfb6-805df6e10b90/resourceGroups/opal-fines-service-data-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-fines-service-test"
      "user-service"  = "/subscriptions/3eec5bde-7feb-4566-bfb6-805df6e10b90/resourceGroups/opal-user-service-data-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-user-service-test"
      "file-handler"  = "/subscriptions/3eec5bde-7feb-4566-bfb6-805df6e10b90/resourceGroups/opal-file-handler-data-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-file-handler-test"
    }
    stg = {
      "fines-service"       = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-fines-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-fines-service-stg"
      "user-service"        = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-user-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-user-service-stg"
      "file-handler"        = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-file-handler-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-file-handler-stg"
      "maintenance-service" = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-maintenance-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-maintenance-service-stg"
      "logging-service"     = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-logging-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-logging-service-stg"
      "log-audit-service"   = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-log-audit-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-log-audit-service-stg"
      "print-service"       = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-print-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-print-service-stg"
    }
  }

  legacy_postgresql_servers = {
    for key, server in local.legacy_postgresql_all_servers : key => merge(server, {
      server_id = try(local.legacy_postgresql_server_ids_by_env[var.env][key], null)
    })
    if contains(server.enabled_envs, var.env) && try(local.legacy_postgresql_server_ids_by_env[var.env][key], null) != null
  }

  consolidated_postgresql_enabled = contains(["demo", "ithc"], var.env)

  consolidated_postgresql_databases = {
    FINES        = "opal-fines-db"
    USER         = "opal-user-db"
    MAINTENANCE  = "opal-maintenance-db"
    LOGGING      = "opal-logging-db"
    LOG_AUDIT    = "opal-log-audit-db"
    FILE_HANDLER = "opal-file-db"
    PRINT        = "opal-print-db"
  }

  service_keyvault_databases_prefix = {
    FINES        = "fines-service"
    USER         = "user-service"
    LOGGING      = "logging-service"
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
