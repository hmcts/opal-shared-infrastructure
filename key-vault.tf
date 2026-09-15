module "opal_key_vault" {
  source = "git@github.com:hmcts/cnp-module-key-vault?ref=DTSPO-31965/remove-jenkins-ptl-access"

  name                     = "${var.product}-${var.env}"
  product                  = var.product
  env                      = var.env
  object_id                = var.jenkins_AAD_objectId
  resource_group_name      = azurerm_resource_group.opal_resource_group.name
  product_group_name       = "DTS Green on Black"
  create_managed_identity  = true
  developers_group         = var.developers_group
  grant_dev_jenkins_access = var.env == "stg"
  common_tags              = var.common_tags
  jenkins_object_id        = data.azurerm_user_assigned_identity.jenkins.principal_id
}

resource "random_string" "session-secret" {
  length = 16
}

resource "random_string" "cookie-secret" {
  length = 16
}

resource "random_string" "csrf-secret" {
  length = 16
}

resource "azurerm_key_vault_secret" "opal-frontend-session-secret" {
  name         = "opal-frontend-session-secret"
  value        = random_string.session-secret.result
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "opal-frontend-cookie-secret" {
  name         = "opal-frontend-cookie-secret"
  value        = random_string.cookie-secret.result
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "opal-frontend-csrf-secret" {
  name         = "opal-frontend-csrf-secret"
  value        = random_string.csrf-secret.result
  key_vault_id = module.opal_key_vault.key_vault_id
}
