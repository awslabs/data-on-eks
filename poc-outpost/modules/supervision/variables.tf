variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
}


variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}

variable "cluster_version" {
  description = "EKS Cluster version"
  type        = string
}


variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "kubernetes_storage_class_default_id" {
  description = "ID of the default Kubernetes storage class"
  type        = string
}

variable "enable_amazon_prometheus" {
  description = "Enable Amazon Prometheus for monitoring"
  type        = bool
}

variable "enable_amazon_grafana" {
  description = "Enable Amazon Grafana for monitoring"
  type        = bool
}

