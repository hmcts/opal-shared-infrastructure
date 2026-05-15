# Existing service-owned PostgreSQL flexible servers.
#
# These definitions mirror the database infrastructure currently held in the
# individual service repositories. They are intended to be adopted into this
# repo with Terraform state moves/imports so the Azure resources, data and
# Key Vault secret names remain unchanged.

module "legacy_postgresql" {
  for_each = local.legacy_postgresql_servers

  providers = {
    azurerm.postgres_network = azurerm
  }

  source = "git@github.com:hmcts/terraform-module-postgresql-flexible?ref=master"

  env                  = var.env
  product              = var.product
  component            = each.value.component
  business_area        = "sds"
  collation            = local.db_collation
  common_tags          = var.common_tags
  admin_user_object_id = var.jenkins_AAD_objectId

  pgsql_databases            = each.value.pgsql_databases
  pgsql_server_configuration = each.value.pgsql_server_configuration
  pgsql_version              = local.db_version
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_USER" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-USER"
  value        = contains(local.consolidated_postgresql_legacy_secret_cutover_keys, each.key) ? module.opal_consolidated_postgresql[0].username : module.legacy_postgresql[each.key].username
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_PASS" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-PASS"
  value        = contains(local.consolidated_postgresql_legacy_secret_cutover_keys, each.key) ? module.opal_consolidated_postgresql[0].password : module.legacy_postgresql[each.key].password
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_HOST" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-HOST"
  value        = contains(local.consolidated_postgresql_legacy_secret_cutover_keys, each.key) ? module.opal_consolidated_postgresql[0].fqdn : module.legacy_postgresql[each.key].fqdn
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_PORT" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-PORT"
  value        = local.db_port
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_DATABASE" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-DATABASE"
  value        = each.value.db_name
  key_vault_id = module.opal_key_vault.key_vault_id
}
