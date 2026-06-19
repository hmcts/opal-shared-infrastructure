variable "product" {}

variable "component" {}

variable "location" {
  default = "UK South"
}

variable "env" {}

variable "subscription" {}

variable "common_tags" {
  type = map(string)
}

variable "jenkins_AAD_objectId" {
  description = "(Required) The Azure AD object ID of a user, service principal or security group in the Azure Active Directory tenant for the vault. The object ID must be unique for the list of access policies."
}

variable "businessArea" {
  default = "sds"
}

variable "aks_subscription_id" {}


variable "developers_group" {
  default = "DTS SDS Developers"
}

variable "service_bus_sku" {
  default = "Standard"
}

variable "valcon_servicebus_topic_names" {
  description = "List of Valcon Service Bus topic names to create. One Key Vault secret per topic is also created."
  type        = list(string)
  default = [
    "courts",
    "organisations",
    "offences",
    "opal-results",
    "opal-application-register"
  ]
}
variable "private_dns_subscription_id" {
  default = "1baf5470-1c3e-40d3-a6f7-74bfbce4b348"
}
