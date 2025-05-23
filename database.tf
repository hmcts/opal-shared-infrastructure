provider "azurerm" {
  features {}
  skip_provider_registration = true
  alias                      = "postgres_network"
  subscription_id            = var.aks_subscription_id
}

data "azurerm_subscription" "opal" {}

resource "azurerm_key_vault_secret" "POSTGRES-USER" {
  name         = "${var.component}-POSTGRES-USER"
  value        = module.opal_postgresql.username
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "POSTGRES-PASS" {
  name         = "${var.component}-POSTGRES-PASS"
  value        = module.opal_postgresql.password
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "POSTGRES_HOST" {
  name         = "${var.component}-POSTGRES-HOST"
  value        = module.opal_postgresql.fqdn
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "POSTGRES_PORT" {
  name         = "${var.component}-POSTGRES-PORT"
  value        = 5432
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "POSTGRES_FINES_DATABASE" {
  name         = "${var.component}-POSTGRES-FINES-DATABASE"
  value        = local.db_fines_name
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "POSTGRES_USER_DATABASE" {
  name         = "${var.component}-POSTGRES-USER-DATABASE"
  value        = local.db_user_name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "opal_postgresql" {
  providers = {
    azurerm.postgres_network = azurerm
  }

  source               = "git@github.com:hmcts/terraform-module-postgresql-flexible?ref=master"
  name                 = "opal-db"
  env                  = var.env
  product              = var.product
  component            = var.component
  business_area        = "sds"
  common_tags          = var.common_tags
  collation            = "en_US.utf8"
  admin_user_object_id = var.jenkins_AAD_objectId
  pgsql_databases = [
    {
      name : local.db_fines_name
    },
    {
      name : local.db_user_name
    },
    {
      name : local.db_maintenance_name
    }
  ]
  pgsql_server_configuration = [
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

  pgsql_version = "16"
}

