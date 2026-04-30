locals {
  db_fines_name        = "psql-${var.product}-fines-db"
  db_user_name         = "psql-${var.product}-user-db"
  db_maintenance_name  = "psql-${var.product}-maintenance-db"
  db_logging_name      = "psql-${var.product}-logging-db"
  db_log_audit_name    = "psql-${var.product}-log-audit-db"
  db_file_handler_name = "psql-${var.product}-file-db"
  db_port              = 5432
}
