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

variable "ray_cluster_version" {
  description = "Namespace for the Ray Cluster"
  type        = string
  default     = "0.4.0"
}

variable "helm_values" {
  description = "Helm values for Ray Cluster helm chart"
  type        = list(any)
  default     = []
}
