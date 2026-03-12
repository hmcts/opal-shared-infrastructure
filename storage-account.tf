module "role_mapping_storage" {
  source = "git@github.com:hmcts/cnp-module-storage-account?ref=4.x"

  env                      = var.env
  storage_account_name     = "opalsa${var.env}"
  resource_group_name      = azurerm_resource_group.opal_resource_group.name
  location                 = azurerm_resource_group.opal_resource_group.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  containers = [
    {
      name        = "rolemapping"
      access_type = "private"
    }
  ]

  public_network_access_enabled = false
  private_endpoint_subnet_id    = data.azurerm_subnet.private_endpoints.id

  team_contact = "#opal"
  common_tags  = var.common_tags
}

resource "azurerm_key_vault_secret" "role_mapping_storage_account_name" {
  name         = "role-mapping-storage-account-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.role_mapping_storage.storageaccount_name
}

resource "azurerm_key_vault_secret" "role_mapping_storage_container_name" {
  name         = "role-mapping-storage-container-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = "rolemapping"
}

resource "azurerm_key_vault_secret" "role_mapping_storage_primary_blob_endpoint" {
  name         = "role-mapping-storage-blob-endpoint"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.role_mapping_storage.storageaccount_primary_blob_endpoint
}

resource "azurerm_key_vault_secret" "role_mapping_storage_primary_access_key" {
  name         = "role-mapping-storage-access-key"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.role_mapping_storage.storageaccount_primary_access_key
}

resource "azurerm_key_vault_secret" "role_mapping_storage_primary_connection_string" {
  name         = "role-mapping-storage-connection-string"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.role_mapping_storage.storageaccount_primary_connection_string
}
