# Import blocks for adopting existing service-owned PostgreSQL infrastructure
# into opal-shared-infrastructure without pg_dump/restore.
#
# Passwords are read from the existing Key Vault secrets and are not imported as
# random_password resources. Importing random_password into the upstream module
# caused forced replacement because the provider cannot import override_special.

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_resource_group.legacy_postgresql[each.key]
  id = "/subscriptions/${split("/", each.value.server_id)[2]}/resourceGroups/${each.value.resource_group_name}"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_postgresql_flexible_server.legacy_postgresql[each.key]
  id = each.value.server_id
}

import {
  for_each = local.legacy_postgresql_database_resources

  to = azurerm_postgresql_flexible_server_database.legacy_postgresql[each.key]
  id = each.value.id
}

import {
  for_each = local.legacy_postgresql_configuration_resources

  to = azurerm_postgresql_flexible_server_configuration.legacy_postgresql[each.key]
  id = each.value.id
}

data "azurerm_key_vault_secret" "legacy_POSTGRES_PASS" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-PASS"
  key_vault_id = module.opal_key_vault.key_vault_id
}

data "azurerm_key_vault_secret" "legacy_POSTGRES_USER" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-USER"
  key_vault_id = module.opal_key_vault.key_vault_id
}

data "azurerm_key_vault_secret" "legacy_POSTGRES_HOST" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-HOST"
  key_vault_id = module.opal_key_vault.key_vault_id
}

data "azurerm_key_vault_secret" "legacy_POSTGRES_PORT" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-PORT"
  key_vault_id = module.opal_key_vault.key_vault_id
}

data "azurerm_key_vault_secret" "legacy_POSTGRES_DATABASE" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-DATABASE"
  key_vault_id = module.opal_key_vault.key_vault_id
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_postgresql_flexible_server_active_directory_administrator.legacy_postgresql_platform_admin[each.key]
  id = "${each.value.server_id}/administrators/${data.azuread_group.legacy_postgresql_platform_admin.object_id}"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_postgresql_flexible_server_active_directory_administrator.legacy_postgresql_jenkins_admin[each.key]
  id = "${each.value.server_id}/administrators/${var.jenkins_AAD_objectId}"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_USER[each.key]
  id = data.azurerm_key_vault_secret.legacy_POSTGRES_USER[each.key].id
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_PASS[each.key]
  id = data.azurerm_key_vault_secret.legacy_POSTGRES_PASS[each.key].id
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_HOST[each.key]
  id = data.azurerm_key_vault_secret.legacy_POSTGRES_HOST[each.key].id
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_PORT[each.key]
  id = data.azurerm_key_vault_secret.legacy_POSTGRES_PORT[each.key].id
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_DATABASE[each.key]
  id = data.azurerm_key_vault_secret.legacy_POSTGRES_DATABASE[each.key].id
}
