sftp_users = {
  outbound = {
    home_directory = "outbound"
    permissions = {
      read   = true
      create = true
      list   = true
      write  = true
      delete = true
    }
  }
}
service_bus_sku                    = "Premium"
servicebus_enable_private_endpoint = true