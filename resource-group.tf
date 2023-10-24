resource "azurerm_resource_group" "opal_resource_group" {
  name     = "${var.product}-${var.env}"
  location = var.location

  tags = var.common_tags
}
