###############################################################################
# IFTA Evidence Pipeline - AWS Infrastructure
#
# Creates the foundational AWS resources for the medallion data pipeline:
#   - KMS Customer Managed Key (CMK) for SSE-KMS encryption
#   - S3 buckets: raw (evidence) and curated (bronze/silver/gold zones)
#   - IAM roles for Glue jobs and crawler
#   - Glue Data Catalog database
#   - Athena workgroup with bytes-scanned cap
#
# Usage:
#   terraform init
#   terraform plan  -var-file=example.tfvars
#   terraform apply -var-file=example.tfvars
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  name_prefix   = "${var.project}-${var.environment}"
  bucket_suffix = "${var.project}-${var.environment}-${local.account_id}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

###############################################################################
# KMS - Customer Managed Key for evidence encryption
###############################################################################

resource "aws_kms_key" "evidence" {
  description             = "CMK for ${local.name_prefix} evidence encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "evidence" {
  name          = "alias/${local.name_prefix}-evidence"
  target_key_id = aws_kms_key.evidence.key_id
}

###############################################################################
# S3 - Raw bucket (immutable legal record)
###############################################################################

resource "aws_s3_bucket" "raw" {
  bucket = "raw-${local.bucket_suffix}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.evidence.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# S3 - Curated bucket (bronze, silver, gold zones via prefixes)
###############################################################################

resource "aws_s3_bucket" "curated" {
  bucket = "curated-${local.bucket_suffix}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "curated" {
  bucket = aws_s3_bucket.curated.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "curated" {
  bucket = aws_s3_bucket.curated.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.evidence.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "curated" {
  bucket                  = aws_s3_bucket.curated.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# Glue - Data Catalog database
###############################################################################

resource "aws_glue_catalog_database" "medallion" {
  name        = "${var.project}_medallion"
  description = "Medallion (bronze/silver/gold) catalog for IFTA evidence pipeline"
}

###############################################################################
# IAM - Glue execution role (used by both extraction and transformation jobs)
###############################################################################

resource "aws_iam_role" "glue_job" {
  name = "${local.name_prefix}-glue-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_job_s3_kms_textract" {
  name = "s3-kms-textract"
  role = aws_iam_role.glue_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3RawAndCuratedAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw.arn,
          "${aws_s3_bucket.raw.arn}/*",
          aws_s3_bucket.curated.arn,
          "${aws_s3_bucket.curated.arn}/*"
        ]
      },
      {
        Sid    = "KmsUseForEvidence"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.evidence.arn
      },
      {
        Sid    = "TextractForExtraction"
        Effect = "Allow"
        Action = [
          "textract:AnalyzeExpense",
          "textract:StartExpenseAnalysis",
          "textract:GetExpenseAnalysis",
          "textract:StartDocumentAnalysis",
          "textract:GetDocumentAnalysis"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# IAM - Glue crawler role
###############################################################################

resource "aws_iam_role" "glue_crawler" {
  name = "${local.name_prefix}-glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "glue_crawler_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_crawler_s3_kms" {
  name = "s3-kms-read"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.curated.arn,
          "${aws_s3_bucket.curated.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.evidence.arn
      }
    ]
  })
}

###############################################################################
# Glue - Crawler for bronze layer
###############################################################################

resource "aws_glue_crawler" "bronze" {
  name          = "${local.name_prefix}-bronze-crawler"
  database_name = aws_glue_catalog_database.medallion.name
  role          = aws_iam_role.glue_crawler.arn
  table_prefix  = "bronze_"

  s3_target {
    path = "s3://${aws_s3_bucket.curated.id}/bronze/"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = local.common_tags
}

###############################################################################
# Athena - Workgroup with bytes-scanned cap
###############################################################################

resource "aws_athena_workgroup" "main" {
  name = "${local.name_prefix}-wg"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.curated.id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.evidence.arn
      }
    }

    bytes_scanned_cutoff_per_query = var.athena_bytes_scanned_cap
  }

  tags = local.common_tags
}
