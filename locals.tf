locals {
  db_fines_name            = "psql-${var.product}-fines-db"
  db_user_name             = "psql-${var.product}-user-db"
  db_maintenance_name      = "psql-${var.product}-maintenance-db"
  db_port                  = 5432
}
