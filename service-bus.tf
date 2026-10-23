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
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "logging-pdpl"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-logging-pdpl-queue-name" {
  name         = "servicebus-logging-pdpl-queue-name"
  value        = module.servicebus-queue-logging-pdpl.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-report" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "report"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-report-queue-name" {
  name         = "servicebus-report-queue-name"
  value        = module.servicebus-queue-report.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-auto-payments-process-interface-files" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "auto-payments-process-interface-files"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-auto-payments-process-interface-files-queue-name" {
  name         = "servicebus-auto-payments-process-interface-files-queue-name"
  value        = module.servicebus-queue-auto-payments-process-interface-files.name
  key_vault_id = module.opal_key_vault.key_vault_id
}


module "servicebus-queue-allocate-tills" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "allocate-tills"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  requires_session           = true
  max_delivery_count         = "3"
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-allocate-tills-queue-name" {
  name         = "servicebus-allocate-tills-queue-name"
  value        = module.servicebus-queue-allocate-tills.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-hmrc-checks" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "hmrc-checks"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-hmrc-checks-queue-name" {
  name         = "servicebus-hmrc-checks-queue-name"
  value        = module.servicebus-queue-hmrc-checks.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-banking-interfaces-preprocess-interface-file-fines" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "banking-interfaces-preprocess-interface-file-fines"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-banking-interfaces-preprocess-interface-file-fines-queue-name" {
  name         = "servicebus-banking-interfaces-preprocess-interface-file-fines-queue-name"
  value        = module.servicebus-queue-banking-interfaces-preprocess-interface-file-fines.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-banking-interfaces-preprocess-interface-file-maintenance" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "banking-interfaces-preprocess-interface-file-maintenance"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-banking-interfaces-preprocess-interface-file-maintenance-queue-name" {
  name         = "servicebus-banking-interfaces-preprocess-interface-file-maintenance-queue-name"
  value        = module.servicebus-queue-banking-interfaces-preprocess-interface-file-maintenance.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-rm-publish-draft-casefile" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "rm-publish-draft-casefile-queue"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-rm-publish-draft-casefile-queue-name" {
  name         = "servicebus-rm-publish-draft-casefile-queue-name"
  value        = module.servicebus-queue-rm-publish-draft-casefile.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-create-draft-account" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "create-draft-account-queue"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-create-draft-account-queue-name" {
  name         = "servicebus-create-draft-account-queue-name"
  value        = module.servicebus-queue-create-draft-account.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-vpfpo-acknowledgements" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "VPFPO-acknowledgements-queue"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-vpfpo-acknowledgements-queue-name" {
  name         = "servicebus-vpfpo-acknowledgements-queue-name"
  value        = module.servicebus-queue-vpfpo-acknowledgements.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "servicebus-queue-publish-draft-account" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-queue?ref=4.x"
  name                       = "publish-draft-account-queue"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-queue-publish-draft-account-queue-name" {
  name         = "servicebus-publish-draft-account-queue-name"
  value        = module.servicebus-queue-publish-draft-account.name
  key_vault_id = module.opal_key_vault.key_vault_id
}
module "opal-reference-data-topic" {
  source                     = "git@github.com:hmcts/terraform-module-servicebus-topic?ref=4.x"
  name                       = "opal-reference-data-topic"
  namespace_name             = module.servicebus-namespace.name
  resource_group_name        = azurerm_resource_group.opal_resource_group.name
  depends_on                 = [module.servicebus-namespace]
  managed_identity_object_id = var.csds_managed_identity_object_id
}

resource "azurerm_key_vault_secret" "servicebus-opal-reference-data-topic-name" {
  name         = "servicebus-opal-reference-data-topic-name"
  value        = module.opal-reference-data-topic.name
  key_vault_id = module.opal_key_vault.key_vault_id
}

module "opal-fines-reference-data-subscription" {
  source                               = "git@github.com:hmcts/terraform-module-servicebus-subscription?ref=4.x"
  name                                 = "opal-fines-reference-data-subscription"
  namespace_id                         = module.servicebus-namespace.id
  topic_name                           = module.opal-reference-data-topic.name
  depends_on                           = [module.opal-reference-data-topic]
  managed_identity_object_id           = var.managed_identity_object_id
  requires_session                     = true
  dead_lettering_on_message_expiration = false
}
resource "azurerm_key_vault_secret" "opal-fines-reference-data-subscription-name" {
  name         = "opal-fines-reference-data-subscription-name"
  value        = "opal-fines-reference-data-subscription"
  key_vault_id = module.opal_key_vault.key_vault_id
}
