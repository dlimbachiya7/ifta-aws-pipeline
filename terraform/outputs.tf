output "aws_region" {
  description = "Deployment region"
  value       = var.aws_region
}

output "raw_bucket" {
  description = "S3 bucket holding original evidence files"
  value       = aws_s3_bucket.raw.id
}

output "curated_bucket" {
  description = "S3 bucket holding bronze/silver/gold layers"
  value       = aws_s3_bucket.curated.id
}

output "kms_key_arn" {
  description = "Customer Managed Key ARN for evidence encryption"
  value       = aws_kms_key.evidence.arn
}

output "glue_database_name" {
  description = "Glue Data Catalog database name"
  value       = aws_glue_catalog_database.medallion.name
}

output "glue_job_role_arn" {
  description = "IAM role used by Glue extraction and transformation jobs"
  value       = aws_iam_role.glue_job.arn
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.main.name
}
