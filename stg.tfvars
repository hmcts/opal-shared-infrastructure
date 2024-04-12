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
