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

  # Performance:
  sku_name = "Balanced_B0"

  # Networking:
  public_network_access              = "Disabled"
  create_private_endpoint            = true
  subnet_id                          = data.azurerm_subnet.redis_private_endpoint.id
  private_dns_zone_ids               = ["/subscriptions/${var.private_dns_subscription_id}/resourceGroups/core-infra-intsvc-rg/providers/Microsoft.Network/privateDnsZones/privatelink.redis.azure.net"]
  access_keys_authentication_enabled = true

  # Backup (persistence) options:
  persistence_rdb_backup_frequency = "6h"
}


resource "azurerm_key_vault_secret" "managed_redis_primary_access_key" {
  name         = "managed-redis-primary-access-key"
  value        = module.opal_managed_redis.primary_access_key
  key_vault_id = module.opal_key_vault.key_vault_id
}
resource "azurerm_key_vault_secret" "managed_redis_hostname" {
  name         = "managed-redis-hostname"
  value        = module.opal_managed_redis.hostname
  key_vault_id = module.opal_key_vault.key_vault_id
}
resource "azurerm_key_vault_secret" "managed_redis_port" {
  name         = "managed-redis-port"
  value        = module.opal_managed_redis.port
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "managed_redis_connection_string" {
  name  = "managed-redis-connection-string"
  value = "rediss://:${urlencode(module.opal_managed_redis.primary_access_key)}@${module.opal_managed_redis.hostname}:${module.opal_managed_redis.port}?tls=true"

  key_vault_id = module.opal_key_vault.key_vault_id
}


