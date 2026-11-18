locals {
  # Keep the existing module-owned Sender grant on its current principal.
  reference_data_topic_sender_object_id = var.servicebus_topic_sender_object_id != null ? var.servicebus_topic_sender_object_id : var.csds_managed_identity_object_id
}

# The subscription module already grants the environment's Opal MI Receiver.
# Add Sender without replacing the existing module-owned grant. Where that
# grant already belongs to Opal (ITHC), a duplicate assignment is unnecessary.
resource "azurerm_role_assignment" "opal_reference_data_sender" {
  count = var.managed_identity_object_id != null && var.managed_identity_object_id != local.reference_data_topic_sender_object_id ? 1 : 0

  scope                = module.opal-reference-data-topic.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = var.managed_identity_object_id
  principal_type       = "ServicePrincipal"
}

# Each environment receives only its own reference-data subscription grant.
# Non-production uses DTS Opal Developers NonProd; production uses
# DTS Opal Developers Production. Membership is managed in azure-access.
resource "azurerm_role_assignment" "opal_team_reference_data_receiver" {
  scope                = module.opal-fines-reference-data-subscription.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.servicebus_receiver_group_object_id
  principal_type       = "Group"
}

# These resources manage only RBAC on existing ASO-managed preview entities.
resource "azurerm_role_assignment" "opal_preview_reference_data_sender" {
  for_each = var.servicebus_preview_reference_data_access

  scope                = each.value.topic_id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = var.managed_identity_object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "opal_preview_reference_data_receiver" {
  for_each = var.servicebus_preview_reference_data_access

  scope                = each.value.subscription_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.managed_identity_object_id
  principal_type       = "ServicePrincipal"
}
