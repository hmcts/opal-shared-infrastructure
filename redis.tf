module "opal_redis" {
  source                        = "git@github.com:hmcts/cnp-module-redis?ref=master"
  product                       = var.product
  location                      = "UK South"
  env                           = var.env
  common_tags                   = var.common_tags
  redis_version                 = "6"
  business_area                 = "sds"
  private_endpoint_enabled      = true
  public_network_access_enabled = false
  sku_name                      = var.sku_name
  family                        = var.family
  capacity                      = var.capacity
  resource_group_name           = azurerm_resource_group.opal_resource_group.name

  maxmemory_reserved              = var.maxmemory_reserved
  maxfragmentationmemory_reserved = var.maxfragmentationmemory_reserved
}

resource "azurerm_key_vault_secret" "redis_connection_string" {
  name         = "redis-connection-string"
  value        = "rediss://:${urlencode(module.opal_redis.access_key)}@${module.opal_redis.host_name}:${module.opal_redis.redis_port}?tls=true"
  key_vault_id = module.opal_key_vault.key_vault_id
}
