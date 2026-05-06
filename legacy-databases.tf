# Existing service-owned PostgreSQL flexible servers.
#
# These definitions adopt the database infrastructure currently held in the
# individual service repositories. They intentionally model the legacy resources
# directly instead of using the PostgreSQL module so imported databases/passwords
# can be matched exactly and adopted without replacement.

data "azurerm_client_config" "current" {}

data "azuread_group" "legacy_postgresql_platform_admin" {
  display_name     = local.legacy_postgresql_platform_admin_group
  security_enabled = true
}

data "azuread_service_principal" "legacy_postgresql_jenkins" {
  object_id = var.jenkins_AAD_objectId
}

resource "azurerm_resource_group" "legacy_postgresql" {
  for_each = local.legacy_postgresql_servers

  name     = each.value.resource_group_name
  location = each.value.location
  tags     = var.common_tags

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [tags]
  }
}

resource "azurerm_postgresql_flexible_server" "legacy_postgresql" {
  for_each = local.legacy_postgresql_servers

  name                          = each.value.server_name
  resource_group_name           = azurerm_resource_group.legacy_postgresql[each.key].name
  location                      = azurerm_resource_group.legacy_postgresql[each.key].location
  version                       = each.value.pgsql_version
  public_network_access_enabled = false

  delegated_subnet_id = each.value.delegated_subnet_id
  private_dns_zone_id = local.postgresql_private_dns_zone_id

  administrator_login    = each.value.pgsql_admin_username
  administrator_password = data.azurerm_key_vault_secret.legacy_POSTGRES_PASS[each.key].value

  storage_mb        = each.value.pgsql_storage_mb
  storage_tier      = each.value.pgsql_storage_tier
  auto_grow_enabled = each.value.auto_grow_enabled

  sku_name = each.value.pgsql_sku

  authentication {
    active_directory_auth_enabled = true
    tenant_id                     = data.azurerm_client_config.current.tenant_id
    password_auth_enabled         = true
  }

  tags = var.common_tags

  dynamic "high_availability" {
    for_each = each.value.high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  maintenance_window {
    day_of_week  = "0"
    start_hour   = "03"
    start_minute = "00"
  }

  backup_retention_days        = each.value.backup_retention_days
  geo_redundant_backup_enabled = each.value.geo_redundant_backups

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      administrator_password,
      tags,
      zone,
      high_availability.0.standby_availability_zone,
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "legacy_postgresql" {
  for_each = local.legacy_postgresql_database_resources

  name      = each.value.name
  server_id = azurerm_postgresql_flexible_server.legacy_postgresql[each.value.server_key].id
  collation = each.value.collation
  charset   = each.value.charset

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "legacy_postgresql" {
  for_each = local.legacy_postgresql_configuration_resources

  name      = each.value.name
  server_id = azurerm_postgresql_flexible_server.legacy_postgresql[each.value.server_key].id
  value     = each.value.value
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "legacy_postgresql_platform_admin" {
  for_each = local.legacy_postgresql_servers

  server_name         = azurerm_postgresql_flexible_server.legacy_postgresql[each.key].name
  resource_group_name = azurerm_postgresql_flexible_server.legacy_postgresql[each.key].resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = data.azuread_group.legacy_postgresql_platform_admin.object_id
  principal_name      = local.legacy_postgresql_platform_admin_group
  principal_type      = "Group"
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "legacy_postgresql_jenkins_admin" {
  for_each = local.legacy_postgresql_servers

  server_name         = azurerm_postgresql_flexible_server.legacy_postgresql[each.key].name
  resource_group_name = azurerm_postgresql_flexible_server.legacy_postgresql[each.key].resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.jenkins_AAD_objectId
  principal_name      = data.azuread_service_principal.legacy_postgresql_jenkins.display_name
  principal_type      = "ServicePrincipal"

  depends_on = [
    azurerm_postgresql_flexible_server_active_directory_administrator.legacy_postgresql_platform_admin,
  ]
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_USER" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-USER"
  value        = azurerm_postgresql_flexible_server.legacy_postgresql[each.key].administrator_login
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_PASS" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-PASS"
  value        = data.azurerm_key_vault_secret.legacy_POSTGRES_PASS[each.key].value
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "legacy_POSTGRES_HOST" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-HOST"
  value        = azurerm_postgresql_flexible_server.legacy_postgresql[each.key].fqdn
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
