variable "ray_cluster_name" {
  description = "Name of the Ray Cluster"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS Cluster"
  type        = string
}

variable "namespace" {
  description = "Namespace for the Ray Cluster"
  type        = string
}

variable "serve_config" {
  description = "Ray Service Deployment config"
  type        = any
  default     = {}
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}
