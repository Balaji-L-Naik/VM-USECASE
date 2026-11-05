variable "aws_region" {
  type    = string
  default = "us-east-1"
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
  type      = string
  sensitive = true
}

variable "snowflake_user" {
  type    = string
  default = "kristina"
}

variable "snowflake_private_key" {
  type      = string
  sensitive = true
}