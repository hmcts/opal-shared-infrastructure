module "opal_redis" {
  source                        = "git@github.com:hmcts/cnp-module-redis?ref=master"
  product                       = var.product
  location                      = "UK South"
  env                           = var.env
  name                          = "opal-redis-stg"
  common_tags                   = var.common_tags
  redis_version                 = "6"
  business_area                 = "sds"
  private_endpoint_enabled      = true
  public_network_access_enabled = false
  resource_group_name           = azurerm_resource_group.opal_resource_group.name
}

resource "azurerm_key_vault_secret" "redis_connection_string" {
  name         = "redis-connection-string"
  value        = "rediss://:${urlencode(module.opal_redis.access_key)}@${module.opal_redis.host_name}:${module.opal_redis.redis_port}?tls=true"
  key_vault_id = module.opal_key_vault.key_vault_id
}
