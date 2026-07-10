data "azurerm_subnet" "redis_private_endpoint" {
  name                 = "iaas"
  resource_group_name  = "ss-${var.env}-network-rg"
  virtual_network_name = "ss-${var.env}-vnet"
}

module "opal_managed_redis" {
  source            = "git@github.com:hmcts/terraform-module-azure-managed-redis?ref=main"
  name              = "${var.product}-${var.env}"
  product           = var.product
  component         = var.component
  env               = var.env
  location          = var.location
  common_tags       = var.common_tags
  clustering_policy = "NoCluster"

  # Performance:
  sku_name = "Balanced_B0"

  # Networking:
  public_network_access              = "Disabled"
  create_private_endpoint            = true
  subnet_id                          = data.azurerm_subnet.redis_private_endpoint.id
  private_dns_zone_ids               = ["/subscriptions/${var.private_dns_subscription_id}/resourceGroups/core-infra-intsvc-rg/providers/Microsoft.Network/privateDnsZones/privatelink.redis.azure.net"]
  access_keys_authentication_enabled = false

  # Backup (persistence) options:
  persistence_rdb_backup_frequency = "6h"
}
