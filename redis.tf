module "opal_redis" {
  source                        = "git@github.com:hmcts/cnp-module-redis?ref=master"
  product                       = var.product
  location                      = "UK South"
  env                           = var.env
  common_tags                   = var.common_tags
  redis_version                 = "6"
  sku_name                      = var.sku_name
  family                        = var.family
  capacity                      = var.capacity
  business_area                 = "sds"
  private_endpoint_enabled      = true
  public_network_access_enabled = false
}

resource "azurerm_key_vault_secret" "redis_access_key" {
  name         = "redis-access-key"
  value        = module.opal_redis.access_key
  key_vault_id = data.opal_key_vault.vault_id
}
