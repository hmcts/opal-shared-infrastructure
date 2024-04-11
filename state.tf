terraform {
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.84.0"
    }
    azapi = {
      source  = "Azure/azapi"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}