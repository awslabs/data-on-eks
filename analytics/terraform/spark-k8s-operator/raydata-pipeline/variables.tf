# =============================================================================
# Variables (passed from parent module)
# =============================================================================

variable "aws_region" {
  description = "AWS region (passed from parent module)"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (passed from parent module)"
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket containing Spark logs (passed from parent module)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Ray jobs"
  type        = string
  default     = "raydata"
}

variable "s3_prefix" {
  description = "S3 prefix path for Spark logs"
  type        = string
  default     = "spark-logs/spark-team-a"
}

variable "iceberg_database" {
  description = "Iceberg database name for Ray jobs"
  type        = string
  default     = "raydata_spark_logs"
}


variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "ray-service-account"
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}

variable "ray_config" {
  description = "Ray cluster configuration"
  type = object({
    batch_size      = optional(string, "10000")
    min_workers     = optional(string, "2")
    max_workers     = optional(string, "10")
    initial_workers = optional(string, "2")
  })
  default = {}
}
