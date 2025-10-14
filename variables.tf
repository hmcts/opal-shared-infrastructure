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

variable "family" {
  default     = "C"
  description = "The SKU family/pricing group to use. Valid values are `C` (for Basic/Standard SKU family) and `P` (for Premium). Use P for higher availability, but beware it costs a lot more."
}

variable "sku_name" {
  default     = "Basic"
  description = "The SKU of Redis to use. Possible values are `Basic`, `Standard` and `Premium`."
}

variable "capacity" {
  default     = "1"
  description = "The size of the Redis cache to deploy. Valid values are 1, 2, 3, 4, 5"
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
  }))
  description = "Map of SFTP users to create in the storage account."
  default     = {}
}

variable "developers_group" {
  default = "DTS SDS Developers"
}
