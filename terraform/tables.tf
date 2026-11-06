# ------------------------------------------------------------------------------
# Bronze Layer: Raw POS Tables (all VARCHAR, no casting in bronze)
# ------------------------------------------------------------------------------

resource "snowflake_table" "pos_sales_raw" {
  database = snowflake_database.pos_db.name
  schema   = snowflake_schema.bronze.name
  name     = "VARDHAN_POS_SALES_RAW"

  column {
    name = "STORE_ID"
    type = "VARCHAR"
  }
  column {
    name = "BILL_NO"
    type = "VARCHAR"
  }
  column {
    name = "LINE_NO"
    type = "VARCHAR"
  }
  column {
    name = "BILL_TS"
    type = "VARCHAR"
  }
  column {
    name = "SKU"
    type = "VARCHAR"
  }
  column {
    name = "MEDICINE_NAME"
    type = "VARCHAR"
  }
  column {
    name = "BATCH_NO"
    type = "VARCHAR"
  }
  column {
    name = "EXPIRY_DATE"
    type = "VARCHAR"
  }
  column {
    name = "QTY"
    type = "VARCHAR"
  }
  column {
    name = "MRP"
    type = "VARCHAR"
  }
  column {
    name = "UNIT_PRICE"
    type = "VARCHAR"
  }
  column {
    name = "DISCOUNT_PCT"
    type = "VARCHAR"
  }
  column {
    name = "SOURCE_FILE"
    type = "VARCHAR"
  }
  column {
    name = "SOURCE_ROW_NUMBER"
    type = "NUMBER(38,0)"
  }
  column {
    name = "INGESTED_AT"
    type = "TIMESTAMP_NTZ(9)"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}

# UNCHANGED for now: needs rebuilding once I see the real stock file header
resource "snowflake_table" "pos_stock_raw" {
  database = snowflake_database.pos_db.name
  schema   = snowflake_schema.bronze.name
  name     = "VARDHAN_POS_STOCK_RAW"

  column {
    name     = "STORE_ID"
    type     = "VARCHAR(32)"
    nullable = true
  }
  column {
    name     = "SKU_CODE"
    type     = "VARCHAR(64)"
    nullable = true
  }
  column {
    name     = "CLOSING_STOCK_QTY"
    type     = "NUMBER(38,0)"
    nullable = true
  }
  column {
    name     = "BATCH_NO"
    type     = "VARCHAR(64)"
    nullable = true
  }
  column {
    name     = "EXPIRY_DATE"
    type     = "DATE"
    nullable = true
  }
  column {
    name     = "SNAPSHOT_DATE"
    type     = "DATE"
    nullable = true
  }
  column {
    name     = "INGESTED_AT"
    type     = "TIMESTAMP_NTZ(9)"
    nullable = true
  }
}

# Distributor API returns JSON pages, so store each page as VARIANT
resource "snowflake_table" "distributor_raw" {
  database = snowflake_database.pos_db.name
  schema   = snowflake_schema.bronze.name
  name     = "VARDHAN_DISTRIBUTOR_RAW"

  column {
    name = "PAYLOAD"
    type = "VARIANT"
  }
  column {
    name = "SOURCE_FILE"
    type = "VARCHAR"
  }
  column {
    name = "INGESTED_AT"
    type = "TIMESTAMP_NTZ(9)"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}

resource "snowflake_table" "ref_store_master_raw" {
  database = snowflake_database.pos_db.name
  schema   = snowflake_schema.bronze.name
  name     = "VARDHAN_REF_STORE_MASTER_RAW"

  column {
    name = "STORE_ID"
    type = "VARCHAR"
  }
  column {
    name = "STORE_NAME"
    type = "VARCHAR"
  }
  column {
    name = "CITY"
    type = "VARCHAR"
  }
  column {
    name = "AREA"
    type = "VARCHAR"
  }
  column {
    name = "AREA_MANAGER"
    type = "VARCHAR"
  }
  column {
    name = "MANAGER_SINCE"
    type = "VARCHAR"
  }
  column {
    name = "IS_24H"
    type = "VARCHAR"
  }
  column {
    name = "OPENED_ON"
    type = "VARCHAR"
  }
  column {
    name = "SOURCE_FILE"
    type = "VARCHAR"
  }
  column {
    name = "SOURCE_ROW_NUMBER"
    type = "NUMBER(38,0)"
  }
  column {
    name = "INGESTED_AT"
    type = "TIMESTAMP_NTZ(9)"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}

resource "snowflake_table" "ref_medicine_master_raw" {
  database = snowflake_database.pos_db.name
  schema   = snowflake_schema.bronze.name
  name     = "VARDHAN_REF_MEDICINE_MASTER_RAW"

  column {
    name = "SKU"
    type = "VARCHAR"
  }
  column {
    name = "MEDICINE_NAME"
    type = "VARCHAR"
  }
  column {
    name = "SCHEDULE"
    type = "VARCHAR"
  }
  column {
    name = "MANUFACTURER"
    type = "VARCHAR"
  }
  column {
    name = "SOURCE_FILE"
    type = "VARCHAR"
  }
  column {
    name = "SOURCE_ROW_NUMBER"
    type = "NUMBER(38,0)"
  }
  column {
    name = "INGESTED_AT"
    type = "TIMESTAMP_NTZ(9)"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}