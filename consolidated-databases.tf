# New consolidated PostgreSQL flexible servers for non-prod cutover work.
#
# These are created alongside the existing service-owned PostgreSQL servers.
# The secrets deliberately use new names and are not consumed by applications
# until a later cutover PR.

module "opal_consolidated_postgresql" {
  count = local.consolidated_postgresql_enabled ? 1 : 0

  providers = {
    azurerm.postgres_network = azurerm
  }

  source = "git@github.com:hmcts/terraform-module-postgresql-flexible?ref=master"

  name                 = "opal-consolidated-db"
  env                  = var.env
  product              = var.product
  component            = var.component
  business_area        = "sds"
  common_tags          = var.common_tags
  collation            = local.db_collation
  admin_user_object_id = var.jenkins_AAD_objectId

  pgsql_databases = [
    for db_name in values(local.consolidated_postgresql_databases) : {
      name = db_name
    }
  ]

  pgsql_server_configuration = local.consolidated_postgresql_server_configuration
  pgsql_version              = local.db_version
}

resource "azurerm_key_vault_secret" "CONSOLIDATED_POSTGRES_USER" {
  count = local.consolidated_postgresql_enabled ? 1 : 0

  name         = "${var.product}-CONSOLIDATED-POSTGRES-USER"
  value        = module.opal_consolidated_postgresql[0].username
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "CONSOLIDATED_POSTGRES_PASS" {
  count = local.consolidated_postgresql_enabled ? 1 : 0

  name         = "${var.product}-CONSOLIDATED-POSTGRES-PASS"
  value        = module.opal_consolidated_postgresql[0].password
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "CONSOLIDATED_POSTGRES_HOST" {
  count = local.consolidated_postgresql_enabled ? 1 : 0

  name         = "${var.product}-CONSOLIDATED-POSTGRES-HOST"
  value        = module.opal_consolidated_postgresql[0].fqdn
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "CONSOLIDATED_POSTGRES_PORT" {
  count = local.consolidated_postgresql_enabled ? 1 : 0

  name         = "${var.product}-CONSOLIDATED-POSTGRES-PORT"
  value        = local.db_port
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "CONSOLIDATED_POSTGRES_DATABASES" {
  for_each = local.consolidated_postgresql_enabled ? local.consolidated_postgresql_databases : {}

  name         = "${var.product}-CONSOLIDATED-POSTGRES-${replace(each.key, "_", "-")}-DATABASE"
  value        = each.value
  key_vault_id = module.opal_key_vault.key_vault_id
}
