variable "aws_region" {
  description = "AWS region for resources. ca-central-1 chosen for Canadian data residency."
  type        = string
  default     = "ca-central-1"
}

variable "project" {
  description = "Project identifier used to prefix resource names."
  type        = string
  default     = "ifta"
}

variable "environment" {
  description = "Environment identifier (e.g., dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "athena_bytes_scanned_cap" {
  description = "Per-query bytes scanned cap for the Athena workgroup. 10 GB default."
  type        = number
  default     = 10737418240
}
