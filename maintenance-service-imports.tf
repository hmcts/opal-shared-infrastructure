# Temporary import blocks for adopting the existing STG maintenance-service
# PostgreSQL resources into opal-shared-infrastructure state.
#
# Jenkins #83 failed because Terraform planned to create
# opal-maintenance-service-stg, but Azure already has that flexible server.
# Keep these only for the adoption run, then remove them once the resources are
# present in this repo's Terraform state.
#
# Do not import the maintenance-service database or AAD admins here:
# the STG adoption plans showed those objects do not exist remotely yet, so they
# should be created by Terraform after the existing server has been imported.

locals {
  maintenance_service_legacy_imports = var.env == "stg" ? {
    "maintenance-service" = {
      server_id          = "/subscriptions/74dacd4f-a248-45bb-a2f0-af700dc4cf68/resourceGroups/opal-maintenance-service-data-stg/providers/Microsoft.DBforPostgreSQL/flexibleServers/opal-maintenance-service-stg"
      configuration_name = "backslash_quote"
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

  to = module.legacy_postgresql[each.key].azurerm_postgresql_flexible_server_configuration.pgsql_server_config[each.value.configuration_name]
  id = "${each.value.server_id}/configurations/${each.value.configuration_name}"
}
