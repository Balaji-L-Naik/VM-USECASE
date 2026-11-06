# ------------------------------------------------------------------------------
# Storage Integration, File Formats & External Stages
# ------------------------------------------------------------------------------

resource "snowflake_storage_integration" "s3_integration" {
  name    = "VARDHAN_S3_STORAGE_INT"
  comment = "Storage Integration for Vardhan S3 POS Data Bucket"
  type    = "EXTERNAL_STAGE"

  enabled                   = true
  storage_provider          = "S3"
  storage_aws_role_arn      = aws_iam_role.snowflake_s3_role.arn
  storage_allowed_locations = ["s3://${var.s3_bucket_name}/"]
}

resource "snowflake_file_format" "csv_format" {
  name        = "VARDHAN_CSV_FORMAT"
  database    = snowflake_database.pos_db.name
  schema      = snowflake_schema.staging.name
  format_type = "CSV"

  field_delimiter                 = ","
  skip_header                     = 1
  field_optionally_enclosed_by    = "\""
  null_if                         = ["NULL", "null", ""]
  empty_field_as_null             = true
  error_on_column_count_mismatch = false
}

resource "snowflake_stage" "s3_pos_stage" {
  name                = "VARDHAN_S3_POS_STAGE"
  database            = snowflake_database.pos_db.name
  schema              = snowflake_schema.staging.name
  url                 = "s3://${var.s3_bucket_name}/"
  storage_integration = snowflake_storage_integration.s3_integration.name
  file_format         = "TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '\"' NULL_IF = ('NULL', 'null', '') EMPTY_FIELD_AS_NULL = TRUE"
  comment             = "External S3 stage for POS raw data ingestion"

  depends_on = [
    snowflake_storage_integration.s3_integration,
    snowflake_file_format.csv_format
  ]
}