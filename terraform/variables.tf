variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "s3_bucket_name" {
  type    = string
  default = "usecases-de"
}

variable "sns_alert_email" {
  type    = string
  default = "kristina.maskarenkhas@diactoventures.com"
}

variable "snowflake_account" {
  type = string
}

variable "snowflake_user" {
  type = string
}

variable "snowflake_role" {
  type    = string
  default = "RSA"
}

variable "snowflake_warehouse" {
  type    = string
  default = "COMPUTE_WH"
}

variable "snowflake_database" {
  type    = string
  default = "VARDHAN_POS_DB"
}

variable "snowflake_schema" {
  type    = string
  default = "VARDHAN_BRONZE"
}

variable "snowflake_private_key_path" {
  type    = string
  default = "rsa_key.p8"
}

variable "snowflake_private_key" {
  type    = string
  default = ""
}