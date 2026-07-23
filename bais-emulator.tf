locals {
  isNotProdCount = var.env == "prod" ? 0 : 1

  bais_emulator_containers = distinct([
    for mapping in var.bais_emulator_sftp_mappings : mapping.container_name
  ])

  bais_emulator_user_mappings = {
    for mapping in var.bais_emulator_sftp_mappings : "${mapping.user_name}:${mapping.container_name}" => {
      user_name      = mapping.user_name
      container_name = mapping.container_name
    }
  }
}

data "azurerm_key_vault_secret" "bais_emulator_public_key" {
  name         = "bais-emulator-public-key"
  count        = local.isNotProdCount
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "opal_file_handler_service_bais_emulator" {
  source                   = "git@github.com:hmcts/cnp-module-storage-account?ref=4.x"
  count                    = local.isNotProdCount
  env                      = var.env
  storage_account_name     = "opalsabais${var.env}"
  resource_group_name      = azurerm_resource_group.opal_resource_group.name
  location                 = azurerm_resource_group.opal_resource_group.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  account_kind = "StorageV2"
  enable_hns   = true
  enable_sftp  = true

  containers = [
    for container_name in local.bais_emulator_containers : {
      name        = container_name
      access_type = "private"
    }
  ]

  public_network_access_enabled = false
  private_endpoint_subnet_id    = data.azurerm_subnet.private_endpoints.id

  team_contact     = "#opal"
  common_tags      = var.common_tags
  defender_enabled = true
}

resource "azurerm_storage_account_local_user" "bais_emulator_users" {
  for_each = local.isNotProdCount == 1 ? local.bais_emulator_user_mappings : {}

  name               = lookup(each.value, "user_name")
  storage_account_id = module.opal_file_handler_service_bais_emulator[0].storageaccount_id

  ssh_key_enabled      = true
  ssh_password_enabled = false
  home_directory       = lookup(each.value, "container_name")

  ssh_authorized_key {
    description = "bais-emulator-public-key"
    key         = trimspace(data.azurerm_key_vault_secret.bais_emulator_public_key[0].value)
  }

  permission_scope {
    permissions {
      read   = true
      create = true
      delete = true
      write  = true
      list   = true
    }

    service       = "blob"
    resource_name = lookup(each.value, "container_name")
  }
}

resource "azurerm_key_vault_secret" "bais_emulator_user_sftp_connection_strings" {
  for_each     = local.isNotProdCount == 1 ? local.bais_emulator_user_mappings : {}
  name         = "bais-emulator-${each.value.user_name}-${each.value.container_name}-sftp-connection-string"
  key_vault_id = module.opal_key_vault.key_vault_id
  value = format(
    "sftp://%s.%s@%s.blob.core.windows.net",
    module.opal_file_handler_service_bais_emulator[0].storageaccount_name,
    azurerm_storage_account_local_user.bais_emulator_users[each.key].name,
    module.opal_file_handler_service_bais_emulator[0].storageaccount_name
  )
}

resource "azurerm_key_vault_secret" "bais_emulator_storage_account_name" {
  count        = local.isNotProdCount
  name         = "bais-emulator-storage-account-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_file_handler_service_bais_emulator[0].storageaccount_name
}

resource "azurerm_key_vault_secret" "bais_emulator_storageaccount_primary_blob_endpoint" {
  count        = local.isNotProdCount
  name         = "bais-emulator-storage-account-primary-blob-endpoint"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.opal_file_handler_service_bais_emulator[0].storageaccount_primary_blob_endpoint
}