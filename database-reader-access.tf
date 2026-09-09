# These grants are owned by OPAL. Shared PostgreSQL module calls stay unchanged.
data "azuread_group" "opal_database_reader" {
  display_name     = local.postgresql_reader_group_name
  security_enabled = true
}

data "azuread_service_principal" "opal_database_provisioner" {
  object_id = var.jenkins_AAD_objectId
}

locals {
  opal_reader_servers = merge(
    {
      for key, config in local.postgresql_all_enabed_servers_none_consolidated : key => {
        host      = module.legacy_postgresql[key].fqdn
        owner     = module.legacy_postgresql[key].username
        databases = sort([for db in config.pgsql_databases : db.name])
      }
    },
    local.consolidated_postgresql_enabled ? {
      consolidated = {
        host      = module.opal_consolidated_postgresql[0].fqdn
        owner     = module.opal_consolidated_postgresql[0].username
        databases = sort([for db in values(local.consolidated_postgresql_databases) : db.db_name])
      }
    } : {}
  )
}

resource "null_resource" "opal_database_reader" {
  for_each = local.opal_reader_servers

  triggers = {
    script_hash     = filesha256("${path.module}/bin/configure_database_reader.py")
    host            = each.value.host
    owner           = each.value.owner
    databases       = jsonencode(each.value.databases)
    reader_name     = local.postgresql_reader_group_name
    reader_id       = data.azuread_group.opal_database_reader.object_id
    admin_id        = var.jenkins_AAD_objectId
    grants_revision = "opal-db-reader-access-v1"
  }

  provisioner "local-exec" {
    command = "python3 ${path.module}/bin/configure_database_reader.py"
    environment = {
      PGHOST           = each.value.host
      PGUSER           = data.azuread_service_principal.opal_database_provisioner.display_name
      OPAL_DB_OWNER    = each.value.owner
      OPAL_DATABASES   = jsonencode(each.value.databases)
      OPAL_READER_NAME = local.postgresql_reader_group_name
      OPAL_READER_ID   = data.azuread_group.opal_database_reader.object_id
    }
  }

  # Includes the existing module-managed Jenkins Entra admin setup.
  depends_on = [module.legacy_postgresql, module.opal_consolidated_postgresql]
}
