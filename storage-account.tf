locals {
  private_endpoint_rg_name   = var.businessArea == "sds" ? "ss-${var.env}-network-rg" : "${var.businessArea}-${var.env}-network-rg"
  private_endpoint_vnet_name = var.businessArea == "sds" ? "ss-${var.env}-vnet" : "${var.businessArea}-${var.env}-vnet"
}

data "azurerm_subnet" "private_endpoints" {
  resource_group_name  = local.private_endpoint_rg_name
  virtual_network_name = local.private_endpoint_vnet_name
  name                 = "private-endpoints"
}

module "opal_storage" {
  source = "git@github.com:hmcts/cnp-module-storage-account?ref=4.x"

  env                      = var.env
  storage_account_name     = "opalsa${var.env}"
  resource_group_name      = azurerm_resource_group.opal_resource_group.name
  location                 = azurerm_resource_group.opal_resource_group.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  containers = [
    {
      name        = "rolemapping"
      access_type = "private"
    },
    {
      name        = "reports"
      access_type = "private"
    }
  ]

  public_network_access_enabled = false
  private_endpoint_subnet_id    = data.azurerm_subnet.private_endpoints.id

  team_contact = "#opal"
  common_tags  = var.common_tags
}


resource "azurerm_key_vault_secret" "role_mapping_storage_container_name" {
  name         = "role-mapping-storage-container-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = "rolemapping"
}

resource "azurerm_key_vault_secret" "reports_storage_container_name" {
  name         = "reports-storage-container-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = "reports"
}

resource "azurerm_key_vault_secret" "storage_primary_blob_endpoint" {
  name         = "storage-blob-endpoint"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_storage.storageaccount_primary_blob_endpoint
}
resource "azurerm_key_vault_secret" "storage_account_name" {
  name         = "storage-account-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_storage.storageaccount_name
}
resource "azurerm_key_vault_secret" "storage_primary_access_key" {
  name         = "storage-access-key"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_storage.storageaccount_primary_access_key
}

resource "azurerm_key_vault_secret" "storage_primary_connection_string" {
  name         = "storage-connection-string"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_storage.storageaccount_primary_connection_string
}


module "opal_file_handler_storage" {
  source = "git@github.com:hmcts/cnp-module-storage-account?ref=4.x"

  env                      = var.env
  storage_account_name     = "opal-file-handler-store"
  resource_group_name      = azurerm_resource_group.opal_resource_group.name
  location                 = azurerm_resource_group.opal_resource_group.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  containers = [
    {
      name        = "BTEckoh-report"
      access_type = "private"
    },
    {
      name        = "CAPS-report"
      access_type = "private"
    }
  ]

  public_network_access_enabled = false
  private_endpoint_subnet_id    = data.azurerm_subnet.private_endpoints.id

  team_contact = "#opal"
  common_tags  = var.common_tags

  defender_enabled = true
}


resource "azurerm_key_vault_secret" "BTEckoh_report_container_name" {
  name         = "BTEckoh-report-container-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = "BTEckoh-report"
}

resource "azurerm_key_vault_secret" "CAPS_report_container_name" {
  name         = "CAPS-report-container-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = "CAPS-report"
}

resource "azurerm_key_vault_secret" "opal_file_handler_storage_primary_blob_endpoint" {
  name         = "opal-file-handler-storage-blob-endpoint"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_file_handler_storage.storageaccount_primary_blob_endpoint
}

resource "azurerm_key_vault_secret" "opal_file_handler_storage_account_name" {
  name         = "opal-file-handler-storage-account-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_file_handler_storage.storageaccount_name
}

resource "azurerm_key_vault_secret" "opal_file_handler_storage_primary_access_key" {
  name         = "opal-file-handler-storage-access-key"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_file_handler_storage.storageaccount_primary_access_key
}

resource "azurerm_key_vault_secret" "opal_file_handler_storage_primary_connection_string" {
  name         = "opal-file-handler-storage-connection-string"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_file_handler_storage.storageaccount_primary_connection_string
}
