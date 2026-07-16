provider "azurerm" {
  features {}
}

provider "tls" {}

provider "random" {}

data "azurerm_user_assigned_identity" "jenkins" {
  name                = "jenkins-${var.env}-mi"
  resource_group_name = "managed-identities-${var.env}-rg"
}