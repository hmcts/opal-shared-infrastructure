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

variable "sftp_access_AAD_objectId" {
  description = "Object ID of the group you wish to give access to the SFTP storage account via access policy"
}

variable "sftp_allowed_key_secrets" {
  description = "A list of names of public keys in the vault to allow access to"
  type        = list(string)
  default     = []
}

variable "sftp_allowed_sa_subnets" {
  description = "Subnets allowed to access storage account"
  type        = list(string)
  default     = []
}