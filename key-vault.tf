module "opal_key_vault" {
  source = "git@github.com:hmcts/cnp-module-key-vault?ref=master"

  name                    = "${var.product}-${var.env}"
  product                 = var.product
  env                     = var.env
  object_id               = var.jenkins_AAD_objectId
  resource_group_name     = azurerm_resource_group.opal_resource_group.name
  product_group_name      = "DTS Green on Black"
  create_managed_identity = true

  common_tags = var.common_tags
}

data "azurerm_key_vault" "key_vault" {
  name                = "${var.product}-${var.env}"
  resource_group_name = "${var.product}-${var.env}"
}

resource "azurerm_key_vault_secret" "POSTGRES-USER" {
  name         = "${var.component}-POSTGRES-USER"
  value        = module.opal-user-db.username
  key_vault_id = data.azurerm_key_vault.key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES-PASS" {
  name         = "${var.component}-POSTGRES-PASS"
  value        = module.opal-user-db.password
  key_vault_id = data.azurerm_key_vault.key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES_HOST" {
  name         = "${var.component}-POSTGRES-HOST"
  value        = module.opal-user-db.fqdn
  key_vault_id = data.azurerm_key_vault.key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES_PORT" {
  name         = "${var.component}-POSTGRES-PORT"
  value        = 5432
  key_vault_id = data.azurerm_key_vault.key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES_FINES_DATABASE" {
  name         = "${var.component}-POSTGRES-FINES-DATABASE"
  value        = local.db_fines_name
  key_vault_id = data.azurerm_key_vault.key_vault.id
}

resource "azurerm_key_vault_secret" "POSTGRES_USER_DATABASE" {
  name         = "${var.component}-POSTGRES-USER-DATABASE"
  value        = local.db_user_name
  key_vault_id = data.azurerm_key_vault.key_vault.id
}
