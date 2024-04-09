locals {
  private_endpoint_rg_name   = var.businessArea == "sds" ? "ss-${var.env}-network-rg" : "${var.businessArea}-${var.env}-network-rg"
  private_endpoint_vnet_name = var.businessArea == "sds" ? "ss-${var.env}-vnet" : "${var.businessArea}-${var.env}-vnet"
}

data "azurerm_subnet" "private_endpoints" {
  resource_group_name  = local.private_endpoint_rg_name
  virtual_network_name = local.private_endpoint_vnet_name
  name                 = "private-endpoints"
}

module "sftp_storage" {
  source                   = "git@github.com:hmcts/cnp-module-storage-account?ref=master"
  env                      = var.env
  storage_account_name     = "opal-sftp${var.env}"
  resource_group_name      = azurerm_resource_group.opal_resource_group.name
  location                 = azurerm_resource_group.opal_resource_group.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  enable_hns               = "true"
  enable_sftp              = "true"

  managed_identity_object_id = var.sftp_access_AAD_objectId
  role_assignments = [
    "Storage Blob Data Contributor"
  ]

  private_endpoint_subscription_id = var.aks_subscription_id
  private_endpoint_subnet_id       = data.azurerm_subnet.private_endpoints.id
  private_endpoint_rg_name         = local.private_endpoint_rg_name

  team_name    = "Opal Team"
  team_contact = "#opal"
  common_tags  = var.common_tags
}

resource "azurerm_storage_container" "sftp_container" {
  name                  = "outbound"
  storage_account_name  = module.sftp_storage.storage_account_name
  container_access_type = "private"
}

data "azurerm_key_vault_secret" "sftp_user_keys" {
  for_each     = toset(var.sftp_allowed_key_secrets)
  name         = each.value #"sftp-user-pub-key"
  key_vault_id = module.opal_key_vault.key_vault_id
}

data "azurerm_key_vault_secret" "sftp_user_name" {
  name         = "sftp-user-name"
  key_vault_id = module.opal_key_vault.key_vault_id
}

data "azurerm_key_vault_secret" "sftp_user_key" {
  name         = "sftp_user_key"
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_storage_account_local_user" "sftp_local_user" {
  name                 = data.azurerm_key_vault_secret.sftp_user_name.value
  storage_account_id   = azurerm_storage_account.sftp_storage.id
  ssh_key_enabled      = true
  ssh_password_enabled = true
  home_directory       = "outbound"

  ssh_authorized_key {
         description = data.azurerm_key_vault_secret.sftp_user_key.name,
         key = data.azurerm_key_vault_secret.sftp_user_key.value
  }

  permission_scope {
    permissions {
      read   = true
      create = true
      list = true
      write = true
      delete = true
    }
    service       = "blob"
    resource_name = azurerm_storage_container.sftp_container.name
  }
}

#TODO: Replace this API call with azurerm_storage_account_local_user resource
resource "azapi_resource" "add_local_user" {
  type      = "Microsoft.Storage/storageAccounts/localUsers@2021-09-01"
  name      = data.azurerm_key_vault_secret.sftp_user_name.value
  parent_id = module.sftp_storage.storageaccount_id

  body = jsonencode({
    properties = {
      "permissionScopes" : [
        {
          "permissions" : "rwdcl",
          "service" : "blob",
          "resourceName" : "outbound"
        }
      ],
      "hasSshPassword" : true,
      "sshAuthorizedKeys" : [
        for k in data.azurerm_key_vault_secret.sftp_user_keys : {
          "description" : k.name,
          "key" : k.value
        }
      ],
      "homeDirectory" : "outbound"
    }
  })
}