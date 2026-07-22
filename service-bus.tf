module "servicebus-namespace" {
  providers = {
    azurerm.private_endpoint = azurerm.private_endpoint
  }
  source              = "git@github.com:hmcts/terraform-module-servicebus-namespace?ref=4.x"
  name                = "${var.product}-servicebus-${var.env}"
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  location            = var.location
  env                 = var.env
  common_tags         = var.common_tags
  sku                 = var.service_bus_sku
  project             = var.businessArea
}

output "sb_primary_send_and_listen_connection_string" {
  value     = module.servicebus-namespace.primary_send_and_listen_connection_string
  sensitive = true
}

output "sb_primary_send_and_listen_shared_access_key" {
  value     = module.servicebus-namespace.primary_send_and_listen_shared_access_key
  sensitive = true
}

resource "azurerm_key_vault_secret" "servicebus_primary_connection_string" {
  name         = "servicebus-connection-string"
  value        = module.servicebus-namespace.primary_send_and_listen_connection_string
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "servicebus_primary_shared_access_key" {
  name         = "servicebus-shared-access-key"
  value        = module.servicebus-namespace.primary_send_and_listen_shared_access_key
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-logging-pdpl" {
  source              = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                = "logging-pdpl"
  namespace_name      = module.servicebus-namespace.name
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  depends_on          = [module.servicebus-namespace]
}

resource "azurerm_key_vault_secret" "servicebus-queue-logging-pdpl-queue-name" {
  name         = "servicebus-logging-pdpl-queue-name"
  value        = module.servicebus-queue-logging-pdpl.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-report" {
  source              = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                = "report"
  namespace_name      = module.servicebus-namespace.name
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  depends_on          = [module.servicebus-namespace]
}

resource "azurerm_key_vault_secret" "servicebus-queue-report-queue-name" {
  name         = "servicebus-report-queue-name"
  value        = module.servicebus-queue-report.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-auto-payments-process-interface-files" {
  source              = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                = "auto-payments-process-interface-files"
  namespace_name      = module.servicebus-namespace.name
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  depends_on          = [module.servicebus-namespace]
}

resource "azurerm_key_vault_secret" "servicebus-queue-auto-payments-process-interface-files-queue-name" {
  name         = "servicebus-auto-payments-process-interface-files-queue-name"
  value        = module.servicebus-queue-auto-payments-process-interface-files.name
  key_vault_id = module.opal_key_vault.key_vault_id
}


module "servicebus-queue-allocate-tills" {
  source              = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                = "allocate-tills"
  namespace_name      = module.servicebus-namespace.name
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  requires_session    = true
  max_delivery_count  = "3"
  depends_on          = [module.servicebus-namespace]
}

resource "azurerm_key_vault_secret" "servicebus-queue-allocate-tills-queue-name" {
  name         = "servicebus-allocate-tills-queue-name"
  value        = module.servicebus-queue-allocate-tills.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-banking-interfaces-preprocess-interface-file-fines" {
  source              = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                = "banking-interfaces-preprocess-interface-file-fines"
  namespace_name      = module.servicebus-namespace.name
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  depends_on          = [module.servicebus-namespace]
}

resource "azurerm_key_vault_secret" "servicebus-queue-banking-interfaces-preprocess-interface-file-fines-queue-name" {
  name         = "servicebus-banking-interfaces-preprocess-interface-file-fines-queue-name"
  value        = module.servicebus-queue-banking-interfaces-preprocess-interface-file-fines.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-banking-interfaces-preprocess-interface-file-maintenance" {
  source              = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                = "banking-interfaces-preprocess-interface-file-maintenance"
  namespace_name      = module.servicebus-namespace.name
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  depends_on          = [module.servicebus-namespace]
}

resource "azurerm_key_vault_secret" "servicebus-queue-banking-interfaces-preprocess-interface-file-maintenance-queue-name" {
  name         = "servicebus-banking-interfaces-preprocess-interface-file-maintenance-queue-name"
  value        = module.servicebus-queue-banking-interfaces-preprocess-interface-file-maintenance.name
  key_vault_id = module.opal_key_vault.key_vault_id
}