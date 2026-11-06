# ------------------------------------------------------------------------------
# Roles & Privileges
# ------------------------------------------------------------------------------

resource "snowflake_role" "vardhan_de_role" {
  name    = "VARDHAN_DATA_ENGINEER_ROLE"
  comment = "Role for Vardhan Data Engineering Pipeline Tasks"
}

resource "snowflake_grant_privileges_to_account_role" "db_grant" {
  account_role_name = snowflake_role.vardhan_de_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.pos_db.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema_grant" {
  account_role_name = snowflake_role.vardhan_de_role.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE STAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.pos_db.name}\".\"${snowflake_schema.bronze.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "wh_grant" {
  account_role_name = snowflake_role.vardhan_de_role.name
  privileges        = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.snowflake_warehouse
  }
}