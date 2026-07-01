# Commenting out Redis configuration as already in Staging
module "opal_redis" {
  count         = var.env == "test" ? 0 : 1
  source        = "git@github.com:hmcts/cnp-module-redis?ref=master"
  product       = var.product
  location      = var.location
  env           = var.env
  common_tags   = var.common_tags
  redis_version = "6"
  business_area = "sds"
  sku_name      = var.redis_sku_name
  family        = var.redis_family
  capacity      = var.redis_capacity

  private_endpoint_enabled      = true
  public_network_access_enabled = false
}

resource "azurerm_key_vault_secret" "redis_access_key" {
  count        = var.env == "test" ? 0 : 1
  name         = "redis-access-key"
  value        = module.opal_redis[0].access_key
  key_vault_id = module.opal_key_vault.key_vault_id
}
resource "azurerm_key_vault_secret" "redis_host_name" {
  count        = var.env == "test" ? 0 : 1
  name         = "redis-host-name"
  value        = module.opal_redis[0].host_name
  key_vault_id = module.opal_key_vault.key_vault_id
}
resource "azurerm_key_vault_secret" "redis_redis_port" {
  count        = var.env == "test" ? 0 : 1
  name         = "redis-redis-port"
  value        = module.opal_redis[0].redis_port
  key_vault_id = module.opal_key_vault.key_vault_id
}

resource "azurerm_key_vault_secret" "redis_connection_string" {
  count = var.env == "test" ? 0 : 1
  name  = "redis-connection-string"
  value = "rediss://:${urlencode(module.opal_redis[0].access_key)}@${module.opal_redis[0].host_name}:${module.opal_redis[0].redis_port}?tls=true"

  key_vault_id = module.opal_key_vault.key_vault_id
}
