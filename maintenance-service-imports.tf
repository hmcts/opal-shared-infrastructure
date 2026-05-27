# Temporary import blocks for adopting the existing STG maintenance-service
# PostgreSQL resources into opal-shared-infrastructure state.
#
# Jenkins #83 failed because Terraform planned to create
# opal-maintenance-service-stg, but Azure already has that flexible server.
# Keep these only for the adoption run, then remove them once the resources are
# present in this repo's Terraform state.

locals {
  maintenance_service_legacy_imports = var.env == "stg" ? {
    "maintenance-service" = {
      server_id               = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-maintenance-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-maintenance-service-stg"
      database_name           = "opal-maintenance-db"
      configuration_name      = "backslash_quote"
      platform_admin_group_id = "3c52c98b-07a3-4a97-92b9-298e86bb1ca9"
    }
  } : {}
}

import {
  for_each = local.maintenance_service_legacy_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server.pgsql_server
  id = each.value.server_id
}

import {
  for_each = local.maintenance_service_legacy_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server_database.pg_databases[each.value.database_name]
  id = "${each.value.server_id}/databases/${each.value.database_name}"
}

import {
  for_each = local.maintenance_service_legacy_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server_configuration.pgsql_server_config[each.value.configuration_name]
  id = "${each.value.server_id}/configurations/${each.value.configuration_name}"
}

import {
  for_each = local.maintenance_service_legacy_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server_active_directory_administrator.pgsql_adadmin
  id = "${each.value.server_id}/administrators/${each.value.platform_admin_group_id}"
}

import {
  for_each = local.maintenance_service_legacy_imports

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server_active_directory_administrator.pgsql_principal_admin[0]
  id = "${each.value.server_id}/administrators/${var.jenkins_AAD_objectId}"
}
