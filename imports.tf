# Import blocks for adopting existing service-owned PostgreSQL infrastructure
# into opal-shared-infrastructure without pg_dump/restore.
#
# These imports intentionally target the legacy_postgresql module definitions.
# They should be run before removing DB infrastructure from individual service
# repos. The random_password import requires the current admin passwords to be
# read from the existing Key Vault POSTGRES-PASS secrets so the imported servers
# do not get planned password rotations without committing or passing clear-text
# passwords.

locals {
  legacy_postgresql_imports = {
    for key, server in local.legacy_postgresql_servers : key => {
      component           = server.component
      resource_group_name = split("/", server.server_id)[4]
      server_name         = split("/", server.server_id)[8]
      server_id           = server.server_id
      databases           = server.pgsql_databases
      configurations      = server.pgsql_server_configuration
    }
  }

  legacy_postgresql_database_imports = length(local.legacy_postgresql_imports) == 0 ? {} : merge([
    for key, server in local.legacy_postgresql_imports : {
      for database in server.databases : "${key}/${database.name}" => {
        server_key    = key
        database_name = database.name
        id            = "${server.server_id}/databases/${database.name}"
      }
    }
  ]...)

  legacy_postgresql_configuration_imports = length(local.legacy_postgresql_imports) == 0 ? {} : merge([
    for key, server in local.legacy_postgresql_imports : {
      for configuration in server.configurations : "${key}/${configuration.name}" => {
        server_key         = key
        configuration_name = configuration.name
        id                 = "${server.server_id}/configurations/${configuration.name}"
      }
    }
  ]...)
}

import {
  for_each = local.legacy_postgresql_imports

  to = module.legacy_postgresql[each.key].azurerm_resource_group.rg[0]
  id = "/subscriptions/${split("/", each.value.server_id)[2]}/resourceGroups/${each.value.resource_group_name}"
}

import {
  for_each = local.legacy_postgresql_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server.pgsql_server
  id = each.value.server_id
}

import {
  for_each = local.legacy_postgresql_database_imports

  to = module.legacy_postgresql[each.value.server_key].azurerm_postgresql_flexible_server_database.pg_databases[each.value.database_name]
  id = each.value.id
}

import {
  for_each = local.legacy_postgresql_configuration_imports

  to = module.legacy_postgresql[each.value.server_key].azurerm_postgresql_flexible_server_configuration.pgsql_server_config[each.value.configuration_name]
  id = each.value.id
}

data "azurerm_key_vault_secret" "legacy_POSTGRES_PASS" {
  for_each = local.legacy_postgresql_servers

  name         = "${each.value.component}-POSTGRES-PASS"
  key_vault_id = module.opal_key_vault.key_vault_id
}

import {
  for_each = local.legacy_postgresql_servers

  to = module.legacy_postgresql[each.key].random_password.password
  id = data.azurerm_key_vault_secret.legacy_POSTGRES_PASS[each.key].value
}

import {
  for_each = var.legacy_postgresql_platform_admin_group_object_id == "" ? {} : local.legacy_postgresql_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server_active_directory_administrator.pgsql_adadmin
  id = "${each.value.server_id}/administrators/${var.legacy_postgresql_platform_admin_group_object_id}"
}

import {
  for_each = local.legacy_postgresql_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server_active_directory_administrator.pgsql_principal_admin[0]
  id = "${each.value.server_id}/administrators/${var.jenkins_AAD_objectId}"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_USER[each.key]
  id = "https://${var.product}-${var.env}.vault.azure.net/secrets/${each.value.component}-POSTGRES-USER"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_PASS[each.key]
  id = "https://${var.product}-${var.env}.vault.azure.net/secrets/${each.value.component}-POSTGRES-PASS"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_HOST[each.key]
  id = "https://${var.product}-${var.env}.vault.azure.net/secrets/${each.value.component}-POSTGRES-HOST"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_PORT[each.key]
  id = "https://${var.product}-${var.env}.vault.azure.net/secrets/${each.value.component}-POSTGRES-PORT"
}

import {
  for_each = local.legacy_postgresql_servers

  to = azurerm_key_vault_secret.legacy_POSTGRES_DATABASE[each.key]
  id = "https://${var.product}-${var.env}.vault.azure.net/secrets/${each.value.component}-POSTGRES-DATABASE"
}
