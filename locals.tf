locals {
  db_fines_name       = "psql-${product}-fines-db"
  db_user_name        = "psql-${var.env}-user-db"
  db_maintenance_name = "psql-${var.env}-maintenance-db"
  db_port             = 5432
}
