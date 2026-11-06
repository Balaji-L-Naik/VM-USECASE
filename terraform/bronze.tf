locals {
  stage_fqn = "${snowflake_database.pos_db.name}.${snowflake_schema.staging.name}.${snowflake_stage.s3_pos_stage.name}"
  fmt_fqn   = "${snowflake_database.pos_db.name}.${snowflake_schema.staging.name}.${snowflake_file_format.csv_format.name}"

  # Column lists, in the same order as the CSV files
  bronze_tables = {
    VARDHAN_POS_SALES_RAW = [
      "STORE_ID", "BILL_NO", "LINE_NO", "BILL_TS", "SKU", "MEDICINE_NAME",
      "BATCH_NO", "EXPIRY_DATE", "QTY", "MRP", "UNIT_PRICE", "DISCOUNT_PCT"
    ]
    VARDHAN_REF_STORE_MASTER_RAW = [
      "STORE_ID", "STORE_NAME", "CITY", "AREA", "AREA_MANAGER",
      "MANAGER_SINCE", "IS_24H", "OPENED_ON"
    ]
    VARDHAN_REF_MEDICINE_MASTER_RAW = ["SKU", "MEDICINE_NAME", "SCHEDULE", "MANUFACTURER"]
  }

  csv_loads = {
    pos_history = {
      table   = "VARDHAN_POS_SALES_RAW"
      path    = "data/pos_history/"
      pattern = ".*/VM[0-9]+_20.*[.]csv[.]gz"
    }
    pos_daily_drops = {
      table   = "VARDHAN_POS_SALES_RAW"
      path    = "data/pos_daily_drops/"
      pattern = ".*/VM[0-9]+_20.*[.]csv[.]gz" # excludes VMxxx_stock_ files
    }
    store_master = {
      table   = "VARDHAN_REF_STORE_MASTER_RAW"
      path    = "data/reference/store_master/"
      pattern = ".*store_master_.*[.]csv"
    }
    medicine_master = {
      table   = "VARDHAN_REF_MEDICINE_MASTER_RAW"
      path    = "data/reference/"
      pattern = ".*medicine_master[.]csv"
    }
  }
}

# NOTE: EXECUTE TASK on the account must be granted once in SQL by ACCOUNTADMIN:
#   GRANT EXECUTE TASK ON ACCOUNT TO ROLE RSA;
#   GRANT EXECUTE TASK ON ACCOUNT TO ROLE VARDHAN_DATA_ENGINEER_ROLE;

# CSV load tasks
resource "snowflake_task" "csv_load" {
  for_each             = local.csv_loads
  database             = snowflake_database.pos_db.name
  schema               = snowflake_schema.bronze.name
  name                 = upper("LOAD_${each.key}")
  warehouse            = snowflake_warehouse.compute_wh.name
  schedule             = "60 MINUTE"
  enabled              = true
  user_task_timeout_ms = 10800000

  sql_statement = <<-EOT
    COPY INTO ${snowflake_database.pos_db.name}.${snowflake_schema.bronze.name}.${each.value.table}
      (${join(",", local.bronze_tables[each.value.table])}, SOURCE_FILE, SOURCE_ROW_NUMBER)
    FROM (
      SELECT ${join(",", [for i in range(length(local.bronze_tables[each.value.table])) : format("$%d", i + 1)])},
             METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
      FROM @${local.stage_fqn}/${each.value.path}
    )
    PATTERN = '${each.value.pattern}'
    FILE_FORMAT = (FORMAT_NAME = '${local.fmt_fqn}')
    ON_ERROR = 'CONTINUE'
  EOT

  depends_on = [
    snowflake_table.pos_sales_raw,
    snowflake_table.ref_store_master_raw,
    snowflake_table.ref_medicine_master_raw,
  ]
}

# Distributor JSON load task
resource "snowflake_task" "distributor_load" {
  database  = snowflake_database.pos_db.name
  schema    = snowflake_schema.bronze.name
  name      = "LOAD_DISTRIBUTOR_API"
  warehouse = snowflake_warehouse.compute_wh.name
  schedule  = "60 MINUTE"
  enabled   = true

  sql_statement = <<-EOT
    COPY INTO ${snowflake_database.pos_db.name}.${snowflake_schema.bronze.name}.VARDHAN_DISTRIBUTOR_RAW
      (PAYLOAD, SOURCE_FILE)
    FROM (SELECT $1, METADATA$FILENAME FROM @${local.stage_fqn}/data/distributor_api/)
    PATTERN = '.*[.]json'
    FILE_FORMAT = (TYPE = 'JSON')
    ON_ERROR = 'CONTINUE'
  EOT

  depends_on = [snowflake_table.distributor_raw]
}