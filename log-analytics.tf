resource "azurerm_log_analytics_workspace" "opal_log_analytics" {
  count = var.env == "test" ? 1 : 0

  name                = "${var.product}-${var.env}-workspace"
  location            = azurerm_resource_group.opal_resource_group.location
  resource_group_name = azurerm_resource_group.opal_resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.common_tags
}
