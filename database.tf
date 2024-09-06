provider "azurerm" {
  features {}
  skip_provider_registration = true
  alias                      = "postgres_network"
  subscription_id            = var.aks_subscription_id
}

module "postgresql_flexible" {
  providers = {
    azurerm.postgres_network = azurerm.postgres_network
  }

  source        = "git@github.com:hmcts/terraform-module-postgresql-flexible?ref=master"
  env           = var.env
  product       = var.product
  component     = var.component
  business_area = "sds"
  common_tags   = var.common_tags
  collation     = "en_US.utf8"

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
