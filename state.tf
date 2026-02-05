provider "azurerm" {
  features {}
  skip_provider_registration = true
  alias                      = "private_endpoint"
  subscription_id            = var.aks_subscription_id
}
terraform {
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
    }
  }
}
