module "valcon-servicebus-namespace" {
  providers = {
    azurerm.private_endpoint = azurerm.private_endpoint
  }
  source              = "git@github.com:hmcts/terraform-module-servicebus-namespace?ref=4.x"
  name                = "${var.product}-valcon-servicebus-${var.env}"
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  location            = var.location
  env                 = var.env
  common_tags         = var.common_tags
  sku                 = var.service_bus_sku
  project             = var.businessArea
}

output "valcon-sb_primary_send_and_listen_connection_string" {
  value     = module.valcon-servicebus-namespace.primary_send_and_listen_connection_string
  sensitive = true
}

output "valcon-sb_primary_send_and_listen_shared_access_key" {
  value     = module.valcon-servicebus-namespace.primary_send_and_listen_shared_access_key
  sensitive = true
}

resource "azurerm_key_vault_secret" "valcon-servicebus_primary_connection_string" {
  name         = "valcon-servicebus-connection-string"
  value        = module.valcon-servicebus-namespace.primary_send_and_listen_connection_string
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "valcon-servicebus_primary_shared_access_key" {
  name         = "valcon-servicebus-shared-access-key"
  value        = module.valcon-servicebus-namespace.primary_send_and_listen_shared_access_key
  key_vault_id = module.opal_key_vault.key_vault_id
}

locals {
  # Use sanitized keys for Terraform and Key Vault naming while preserving raw topic names.
  valcon_servicebus_topics = {
    for topic in var.valcon_servicebus_topic_names :
    lower(regexreplace(topic, "[^0-9A-Za-z-]", "-")) => topic
  }
}

module "valcon-servicebus-topic" {
  for_each            = local.valcon_servicebus_topics
  source              = "git@github.com:hmcts/terraform-module-servicebus-topic?ref=master"
  name                = each.value
  namespace_name      = module.valcon-servicebus-namespace.name
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  depends_on          = [module.valcon-servicebus-namespace]
}

resource "azurerm_key_vault_secret" "valcon-servicebus-topic-name" {
  for_each     = module.valcon-servicebus-topic
  name         = "valcon-servicebus-${each.key}-topic-name"
  value        = each.value.name
  key_vault_id = module.opal_key_vault.key_vault_id
}
