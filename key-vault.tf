module "opal_key_vault" {
  source = "git@github.com:hmcts/cnp-module-key-vault?ref=master"

  name                    = "${var.product}-${var.env}"
  product                 = var.product
  env                     = var.env
  object_id               = var.jenkins_AAD_objectId
  resource_group_name     = azurerm_resource_group.opal_resource_group.name
  product_group_name      = "DTS Green on Black"
  create_managed_identity = true
  developers_group        = var.developers_group

  common_tags = var.common_tags
}

