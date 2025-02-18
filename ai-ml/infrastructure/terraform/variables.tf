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
  default     = false
}
variable "bottlerocket_data_disk_snapshot_id" {
  description = "Bottlerocket Data Disk Snapshot ID"
  type        = string
  default     = ""
}
variable "enable_aws_efs_csi_driver" {
  description = "Enable AWS EFS CSI Driver"
  type        = bool
  default     = false
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
variable "enable_amazon_prometheus" {
  description = "Enable Amazon Prometheus"
  type        = bool
  default     = false
}
variable "enable_amazon_emr" {
  description = "Enable Amazon EMR"
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
  default     = false
}
variable "enable_kuberay_operator" {
  description = "Enable KubeRay Operator"
  type        = bool
  default     = false
}
variable "huggingface_token" {
  description = "Hugging Face Secret Token"
  type        = string
  default     = "DUMMY_TOKEN_REPLACE_ME"
  sensitive   = true
}
variable "enable_rayserve_ha_elastic_cache_redis" {
  description = "Flag to enable Ray Head High Availability with Elastic Cache for Redis"
  type        = bool
  default     = false
}

variable "enable_torchx_etcd" {
  description = "Flag to enable etcd deployment for torchx"
  type        = bool
  default     = false
}

# Jupyterhub Specific Variables

# NOTE: You need to use private domain or public domain name with ACM certificate
# Data-on-EKS website docs will show you how to create free public domain name with ACM certificate for testing purpose only
# Example of public domain name(<subdomain-name>.<domain-name>.com): eks.jupyter-doeks.dynamic-dns.com
variable "jupyter_hub_auth_mechanism" {
  type        = string
  description = "Allowed values: cognito, dummy, oauth"
  default     = "dummy"
}

#  Domain name is public so make sure you use a unique while deploying, Only needed if auth mechanism is set to cognito
variable "cognito_custom_domain" {
  description = "Cognito domain prefix for Hosted UI authentication endpoints"
  type        = string
  default     = "eks"
}

# Only needed if auth mechanism is set to cognito
variable "acm_certificate_domain" {
  type        = string
  description = "Enter domain name with wildcard and ensure ACM certificate is created for this domain name, e.g. *.example.com"
  default     = ""
}

# Only needed if auth mechanism is set to cognito or oauth. This is the domain for jupyterhub
variable "jupyterhub_domain" {
  type        = string
  description = "Enter domain name for jupyterhub to be hosted,  e.g. eks.example.com. Only needed if auth mechanism is set to cognito or oauth"
  default     = ""
}

# Only needed if auth mechanism is set to oauth. This is the root path for the oidc endpoints
variable "oauth_domain" {
  type        = string
  description = "Enter oauth domain and endpoint, e.g. https://keycloak.example.com/realms/master/protocol/openid-connect. Only needed if auth mechanism is set to oauth"
  default     = ""
}

# Only needed if auth mechanism is set to oauth. This is the id of the client
variable "oauth_jupyter_client_id" {
  type        = string
  description = "Enter oauth client id for jupyterhub, e.g. jupyterhub. Only needed if auth mechanism is set to oauth"
  default     = ""
}

# Only needed if auth mechanism is set to oauth. This is the secret for the client
variable "oauth_jupyter_client_secret" {
  type        = string
  description = "Enter oauth client secret. Only needed if auth mechanism is set to oauth"
  default     = ""
  sensitive   = true
}

# Only needed if auth mechanism is set to oauth. This is the key to use for looking up the username.
variable "oauth_username_key" {
  type        = string
  description = "oauth field for the username. e.g. 'preferred_username' Only needed if auth mechanism is set to oauth"
  default     = ""
}
