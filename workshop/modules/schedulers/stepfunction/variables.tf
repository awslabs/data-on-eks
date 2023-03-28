variable "job_execution_role_arn" {
  description = "Job exec role of emr-eks cluster"
  type        = string
  default     = "none"
}

variable "virtual_cluster_id" {
  description = "Virtual cluster id of emr-eks cluster"
  type        = string
  default     = "none"
}

variable "s3_bucket_id" {
  description = "S3 bucket name"
  type        = string
  default     = "none"
}
