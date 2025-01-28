variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "ai-stack"
  type        = string
}

variable "region" {
  description = "region"
  default     = "us-east-1"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.30"
  type        = string
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/21"
  type        = string
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

# Infrastructure Variables
variable "enable_aws_cloudwatch_metrics" {
  description = "Enable AWS Cloudwatch Metrics addon"
  type        = bool
  default     = true
}
variable "bottlerocket_data_disk_snapshot_id" {
  description = "Bottlerocket Data Disk Snapshot ID"
  type        = string
  default     = ""
}
variable "enable_aws_efa_k8s_device_plugin" {
  description = "Enable AWS EFA K8s Device Plugin"
  type        = bool
  default     = false
}
variable "enable_aws_fsx_csi_driver"{
  description = "Whether or not to deploy the Fsx Driver"
  type        = bool
  default     = false
}
variable "deploy_fsx_volume" {
  description = "Whether or not to deploy the example Fsx Volume"
  type        = bool
  default     = false
}

# Addon Variables
variable "enable_kube_prometheus_stack" {
  description = "Enable Kube Prometheus addon"
  type        = bool
  default     = false
}
variable "enable_kubecost" {
  description = "Enable Kubecost addon"
  type        = bool
  default     = false
}
variable "enable_argo_workflows" {
  description = "Enable Argo Workflows addon"
  type        = bool
  default     = false
}
variable "enable_argo_events" {
  description = "Enable Argo Events addon"
  type        = bool
  default     = false
}
variable "enable_mlflow_tracking" {
  description = "Enable MLFlow Tracking"
  type        = bool
  default     = false
}
variable "enable_jupyterhub" {
  description = "Enable JupyterHub"
  type        = bool
  default     = false
}
variable "enable_volcano" {
  description = "Enable Volcano"
  type        = bool
  default     = true
}
variable "enable_kuberay_operator" {
  description = "Enable KubeRay Operator"
  type        = bool
  default     = true
}
variable "huggingface_token" {
  description = "Hugging Face Secret Token"
  type        = string
  default     = "DUMMY_TOKEN_REPLACE_ME"
  sensitive   = true
}
