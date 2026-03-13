variable "name" {
  description = "Name to be used on all the resources as identifier"
  default     = "data-on-eks"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 63
    error_message = "Name must be between 1 and 63 characters."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "deployment_id" {
  description = "Deployment ID unique to this stack"
  type        = string
  default     = "abcdefg"
}


#---------------------------------------------------------------
# VPC
#---------------------------------------------------------------

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "VPC CIDR must have a prefix length between /16 and /28."
  }
}

variable "secondary_cidrs" {
  description = "List of secondary CIDR blocks to associate with the VPC"
  type        = list(string)
  # Default includes four /16 blocks (two per AZ for a 2-AZ deployment).
  # Replace these with your own non-overlapping /16 ranges when deploying.
  default = [
    "100.64.0.0/16",
    "100.65.0.0/16",
    "100.66.0.0/16",
    "100.67.0.0/16",
  ]

  validation {
    condition = alltrue([
      for cidr in var.secondary_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All secondary CIDRs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition = alltrue([
      for cidr in var.secondary_cidrs : tonumber(split("/", cidr)[1]) >= 16 && tonumber(split("/", cidr)[1]) <= 28
    ])
    error_message = "All secondary CIDRs must have a prefix length between /16 and /28."
  }
}

variable "public_subnet_tags" {
  description = "Additional tags for the public subnets"
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags for the private subnets"
  type        = map(string)
  default     = {}
}

#---------------------------------------------------------------
# EKS
#---------------------------------------------------------------

variable "eks_cluster_version" {
  description = "Kubernetes `<major>.<minor>` version to use for the EKS cluster (i.e.: `1.31`)"
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.eks_cluster_version))
    error_message = "EKS cluster version must be in format 'major.minor' (e.g., '1.31')."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Indicates whether or not the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "kms_key_admin_roles" {
  description = "A list of IAM roles that will have admin access to the KMS key used by the cluster"
  type        = list(string)
  default     = []
}

# EKS Addons
variable "enable_cluster_addons" {
  description = <<DESC
A map of EKS addon names to boolean values that control whether each addon is enabled.
This allows fine-grained control over which addons are deployed by this Terraform stack.
To enable or disable an addon, set its value to `true` or `false` in your blueprint.tfvars file.
If you need to add a new addon, update this variable definition and also adjust the logic
in the EKS module (e.g., in eks.tf locals) to include any custom configuration needed.
DESC

  type = map(bool)
  default = {
    aws-ebs-csi-driver              = true
    aws-mountpoint-s3-csi-driver    = true
    metrics-server                  = true
    eks-node-monitoring-agent       = true
    amazon-cloudwatch-observability = false
  }
}

variable "managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type        = any
  default     = {}
}

variable "enable_ingress_nginx" {
  description = "Enable ingress-nginx"
  type        = bool
  default     = true
}

variable "enable_jupyterhub" {
  default     = true
  description = "Enable Jupyter Hub"
  type        = bool
}

variable "enable_raydata" {
  description = "Enable Ray Data via ArgoCD"
  type        = bool
  default     = false
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = false
}

variable "enable_datahub" {
  description = "Enable DataHub for metadata management"
  type        = bool
  default     = false
}

variable "enable_pinot" {
  description = "Enable Apache Pinot for real-time analytics"
  type        = bool
  default     = false
}

variable "enable_superset" {
  description = "Enable Apache Superset for data exploration and visualization"
  type        = bool
  default     = false
}

variable "enable_celeborn" {
  description = "Enable Apache Celeborn for remote shuffling service"
  type        = bool
  default     = false
}

variable "enable_airflow" {
  description = "Enable Apache Airflow for workflow orchestration"
  type        = bool
  default     = false
}

variable "enable_ipv6" {
  description = "Enable IPv6 for the EKS cluster and its components"
  type        = bool
  default     = false
}

variable "enable_nvidia_device_plugin" {
  description = "Enable NVIDIA Device plugin addon for GPU workloads"
  type        = bool
  default     = false
}

variable "enable_emr_on_eks" {
  description = "Enable EMR on EKS Virtual Clusters for running Spark jobs"
  type        = bool
  default     = false
}

variable "enable_emr_spark_operator" {
  description = "Enable EMR Spark Operator for declarative Spark job management"
  type        = bool
  default     = false
}

#---------------------------------------------------------------
# EKS Provisioned Control Plane (PCP) Tier
# Controls the EKS control plane capacity for high-scale workloads
#
# Tier Limits (EKS v1.30+):
#   XL  : 1700 API seats | 167 pods/sec | 16 GB etcd
#   2XL : 3400 API seats | 283 pods/sec | 16 GB etcd
#   4XL : 6800 API seats | 400 pods/sec | 16 GB etcd
#
# Key Prometheus Metrics to monitor:
#   - apiserver_flowcontrol_current_executing_seats
#   - scheduler_schedule_attempts_total
#   - apiserver_storage_size_bytes
#---------------------------------------------------------------
variable "eks_pcp_tier" {
  description = <<DESC
EKS Provisioned Control Plane (PCP) scaling tier. Controls the EKS control plane capacity.
Valid values: null (standard/default), "XL", "2XL", "4XL"
- XL  : 1700 API concurrency seats, 167 pods/sec scheduling rate
- 2XL : 3400 API concurrency seats, 283 pods/sec scheduling rate
- 4XL : 6800 API concurrency seats, 400 pods/sec scheduling rate
Leave null to use the default standard tier.
DESC
  type        = string
  default     = null

  validation {
    # contains() will error if the value argument is null, so use coalesce to
    # convert null into an empty string. The overall condition still allows
    # null as a valid value.
    condition     = var.eks_pcp_tier == null || contains(["XL", "2XL", "4XL"], coalesce(var.eks_pcp_tier, ""))
    error_message = "eks_pcp_tier must be null or one of: XL, 2XL, 4XL"
  }
}
