# ------------------------------------------------------------------------------
# Databases & Schemas
# ------------------------------------------------------------------------------

resource "snowflake_database" "pos_db" {
  name    = var.snowflake_database
  comment = "Database for Vardhan Medicals POS Ingestion Pipeline"
}

resource "snowflake_schema" "bronze" {
  database = snowflake_database.pos_db.name
  name     = "VARDHAN_BRONZE"
  comment  = "Bronze Raw Ingestion Schema"
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.pos_db.name
  name     = "VARDHAN_STAGING"
  comment  = "Staging Schema for External Stages & File Formats"
}