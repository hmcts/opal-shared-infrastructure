resource "random_password" "password" {
  count = var.env == "test" ? 1 : 0
  length           = 16
  special          = true
  min_special      = 1
  min_numeric      = 1
  min_lower        = 1
  min_upper        = 1
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "virtual-machine-password" {
  count = var.env == "test" ? 1 : 0
  name         = "virtual-machine-password"
  value        = random_password.password[count.index].result
  key_vault_id = module.opal_key_vault.key_vault_id
}

data "azurerm_subnet" "iaas_private_endpoints" {
  resource_group_name  = local.private_endpoint_rg_name
  virtual_network_name = local.private_endpoint_vnet_name
  name                 = "iaas"
}

provider "azurerm" {
  alias = "soc"
  features {}
  subscription_id = "8ae5b3b6-0b12-4888-b894-4cec33c92292"
}

provider "azurerm" {
  alias = "cnp"
  features {}
  subscription_id = "1c4f0704-a29e-403d-b719-b90c34ef14c9"
}

provider "azurerm" {
  alias = "dcr"
  features {}
  subscription_id = "1c4f0704-a29e-403d-b719-b90c34ef14c9"
}


module "virtual-machine" {
  providers = {
    azurerm     = azurerm
    azurerm.cnp = azurerm.cnp
    azurerm.soc = azurerm.soc
    azurerm.dcr = azurerm.dcr
  }

  source = "git@github.com:hmcts/terraform-module-virtual-machine.git?ref=master"
  count = var.env == "test" ? 2 : 0
  env                  = "test"
  vm_type              = "windows"
  vm_name              = "opal-perf-test-vm-${count.index}"
  vm_resource_group    = azurerm_resource_group.opal_resource_group.name
  vm_admin_password    = random_password.password[0].result
  vm_subnet_id         = data.azurerm_subnet.iaas_private_endpoints.id

  vm_publisher_name    = "microsoftwindowsdesktop"
  vm_offer             = "windows-11"
  vm_sku               = "win11-25h2-pro"

  vm_size              = "D2ds_v5"
  vm_version           = "latest"

  nessus_install             = false
  install_splunk_uf          = false
  install_dynatrace_oneagent = false
  install_azure_monitor      = false

  tags                 = var.common_tags
}
