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
  source                   = "git@github.com:hmcts/cnp-module-storage-account?ref=4.x"
  env                      = var.env
  storage_account_name     = "opalsftp${var.env}"
  resource_group_name      = azurerm_resource_group.opal_resource_group.name
  location                 = azurerm_resource_group.opal_resource_group.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  enable_hns               = "true"
  enable_sftp              = "true"

  containers = [
    {
      name        = "outbound"
      access_type = "private"
    },
    {
      name        = "inbound"
      access_type = "private"
    }
  ]

  private_endpoint_subnet_id = data.azurerm_subnet.private_endpoints.id

  team_contact = "#opal"
  common_tags  = var.common_tags
}

resource "tls_private_key" "sftp_user_key" {
  for_each  = var.sftp_users
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault_secret" "sftp_user_private_key" {
  for_each     = var.sftp_users
  name         = "${each.key}-private-key"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = tls_private_key.sftp_user_key[each.key].private_key_openssh
}

resource "azurerm_key_vault_secret" "sftp_user_public_key" {
  for_each     = var.sftp_users
  name         = "${each.key}-public-key"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = tls_private_key.sftp_user_key[each.key].public_key_openssh
}

resource "azurerm_storage_account_local_user" "sftp_local_user" {
  for_each             = var.sftp_users
  name                 = each.key
  storage_account_id   = module.sftp_storage.storageaccount_id
  ssh_key_enabled      = true
  ssh_password_enabled = true
  home_directory       = each.value.home_directory

  ssh_authorized_key {
    description = "SFTP User Public Key"
    key         = tls_private_key.sftp_user_key[each.key].public_key_openssh
  }

  permission_scope {
    permissions {
      read   = each.value.permissions.read
      create = each.value.permissions.create
      list   = each.value.permissions.list
      write  = each.value.permissions.write
      delete = each.value.permissions.delete
    }
    service       = "blob"
    resource_name = each.key
  }
}

resource "azurerm_key_vault_secret" "sftp_user_password" {
  for_each     = var.sftp_users
  name         = "${each.key}-password"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = azurerm_storage_account_local_user.sftp_local_user[each.key].password
}
