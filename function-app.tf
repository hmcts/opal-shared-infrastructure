data "azurerm_client_config" "current" {}

module "semarchy_opal_function_app" {
  source = "git@github.com:hmcts/cpp-module-terraform-azurerm-functionapp?ref=3d89c1287f3d8e2028f7d1ccfc87e51c66a27bd1"

  resource_group_name = azurerm_resource_group.opal_resource_group.name
  location            = azurerm_resource_group.opal_resource_group.location
  environment         = var.env
  service_plan_name   = "${var.product}-semarchy-opal-asp-${var.env}"

  function_app_name = "${var.product}-semarchy-opal-${var.env}"
  asp_os_type       = "Linux"

  identity = {
    type = "SystemAssigned"
  }

  # Placeholder storage for Durable task hub until a dedicated account is confirmed.
  storage_account_name              = module.opal_storage.storageaccount_name
  storage_account_access_key        = module.opal_storage.storageaccount_primary_access_key
  storage_account_connection_string = module.opal_storage.storageaccount_primary_connection_string

  key_vault_id = module.opal_key_vault.key_vault_id

  site_config = {
    always_on = true
    application_stack = {
      python_version = "3.11"
    }
  }

  tags = var.common_tags
}

resource "azurerm_key_vault_access_policy" "semarchy_opal_function_app_secrets_access" {
  key_vault_id = module.opal_key_vault.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.semarchy_opal_function_app.principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

resource "azurerm_key_vault_secret" "semarchy_opal_function_app_name" {
  name         = "semarchy-opal-function-app-name"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.semarchy_opal_function_app.function_app_name
}

resource "azurerm_key_vault_secret" "semarchy_opal_function_app_url" {
  name         = "semarchy-opal-function-app-url"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = "https://${module.semarchy_opal_function_app.function_app_name}.azurewebsites.net"
}

resource "azurerm_key_vault_secret" "semarchy_opal_function_app_primary_key" {
  name         = "semarchy-opal-function-app-primary-key"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = module.semarchy_opal_function_app.function_app_primary_key
}

resource "azurerm_key_vault_secret" "semarchy_opal_servicebus_connection_string" {
  name         = "semarchy-opal-valcon-servicebus-connection-string"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = azurerm_key_vault_secret.valcon-servicebus_primary_connection_string.value
}

resource "azurerm_key_vault_secret" "semarchy_opal_topic_offences" {
  name         = "semarchy-opal-topic-offences"
  key_vault_id = module.opal_key_vault.key_vault_id
  value        = azurerm_key_vault_secret.valcon-servicebus-topic-name["offences"].value
}
