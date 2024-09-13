# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}



output "automq_s3_data_bucket_url" {
  description = "The URL of the AutoMQ S3 data bucket"
  value = "s3.data.buckets=0@s3://${aws_s3_bucket.automqs3databucket.bucket}?region=${var.region}&endpoint=https://s3.amazonaws.com"
}

output "automq_s3_ops_bucket_url" {
  description = "The URL of the AutoMQ S3 ops bucket"
  value = "s3.ops.buckets=0@s3://${aws_s3_bucket.automqs3opsbucket.bucket}?region=${var.region}&endpoint=https://s3.amazonaws.com"
}

output "automq_s3_wal_bucket_url" {
  description = "The URL of the AutoMQ S3 wal bucket"
  value = "s3.wal.buckets=0@s3://${aws_s3_bucket.automqs3walbucket.bucket}?region=${var.region}&endpoint=https://s3.amazonaws.com"
}

output "automq_prometheus_metrics_uri" {
  value = "rw://?endpoint=${module.prometheus.workspace_prometheus_endpoint}api/v1/remote_write&auth=sigv4&region=${var.region}"
}

output "automq_prometheus_server_url" {
  value = "${module.prometheus.workspace_prometheus_endpoint}"
}



