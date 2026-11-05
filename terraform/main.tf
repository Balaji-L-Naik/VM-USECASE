terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# 1. AWS Secrets Manager: Snowflake Credentials
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "snowflake_credentials" {
  name        = "vardhan/snowflake/credentials"
  description = "Snowflake RSA Key-Pair credentials for Vardhan pipeline"
}

resource "aws_secretsmanager_secret_version" "snowflake_credentials_val" {
  secret_id = aws_secretsmanager_secret.snowflake_credentials.id
  secret_string = jsonencode({
    account     = var.snowflake_account
    user        = var.snowflake_user
    private_key = var.snowflake_private_key
  })
}

# ------------------------------------------------------------------------------
# 2. SNS Alert Topic & Subscription
# ------------------------------------------------------------------------------
resource "aws_sns_topic" "pipeline_alerts" {
  name = "vardhan-pipeline-alerts-prod"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_alert_email
}

# ------------------------------------------------------------------------------
# 3. IAM Execution Role & Custom Policy for Lambda
# ------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "vardhan_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_custom_policy" {
  name = "vardhan_lambda_custom_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.s3_bucket_name}", "arn:aws:s3:::${var.s3_bucket_name}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.pipeline_alerts.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:vardhan/snowflake/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_custom_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_custom_policy.arn
}

# ------------------------------------------------------------------------------
# 4. Lambda Function Packaging & Deployment
# ------------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/pos_preload_validator.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "preload_validation" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "vardhan_preload_validation"
  role             = aws_iam_role.lambda_role.arn
  handler          = "pos_preload_validator.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.pipeline_alerts.arn
    }
  }
}

# ------------------------------------------------------------------------------
# 5. IAM Role & State Machine for Step Functions
# ------------------------------------------------------------------------------
resource "aws_iam_role" "sfn_role" {
  name = "vardhan_step_functions_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "sfn_policy" {
  name = "vardhan_sfn_invoke_lambda_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.preload_validation.arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sfn_policy_attach" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_policy.arn
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "vardhan-pos-ingestion-pipeline"
  role_arn = aws_iam_role.sfn_role.arn

  definition = jsonencode({
    Comment = "Vardhan Medicals POS Pre-Load Validation Workflow"
    StartAt = "ValidateManifestAndDedup"
    States = {
      ValidateManifestAndDedup = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.preload_validation.arn
          Payload = {
            "bucket" = var.s3_bucket_name
            "key.$"  = "$.file_key"
          }
        }
        ResultPath = "$.validation_result"
        Next       = "CheckValidationStatus"
      }
      CheckValidationStatus = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.validation_result.Payload.status"
            StringEquals = "PASSED"
            Next         = "ValidationPassed"
          },
          {
            Variable     = "$.validation_result.Payload.status"
            StringEquals = "QUARANTINED"
            Next         = "ValidationQuarantined"
          }
        ]
        Default = "ValidationSkipped"
      }
      ValidationPassed = {
        Type    = "Succeed"
        Comment = "File validated successfully and ready for Snowflake ingestion."
      }
      ValidationQuarantined = {
        Type  = "Fail"
        Cause = "Manifest mismatch or corrupt data detected."
        Error = "ManifestValidationFailed"
      }
      ValidationSkipped = {
        Type    = "Succeed"
        Comment = "File skipped due to duplicate hash or non-CSV path."
      }
    }
  })
}