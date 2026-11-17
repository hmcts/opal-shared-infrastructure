# Each environment receives only its own reference-data subscription grant.
# Non-production uses DTS Opal Developers NonProd; production uses
# DTS Opal Developers Production. Membership is managed in azure-access.
resource "azurerm_role_assignment" "opal_team_reference_data_receiver" {
  scope                = module.opal-fines-reference-data-subscription.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.servicebus_receiver_group_object_id
  principal_type       = "Group"
}
