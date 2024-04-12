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

variable "sftp_users" {
  type = map(object({
    home_directory = optional(string, "outbound")
    permissions = object({
      read   = optional(bool, true)
      create = optional(bool, true)
      list   = optional(bool, true)
      write  = optional(bool, true)
      delete = optional(bool, true)
    })
  })
  description = "Map of SFTP users to create in the storage account."
  default     = {}
}
