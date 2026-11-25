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
  description = "Unique ID used to tag all AWS resources for this deployment. Enables identification of orphaned resources and cleanup in case of Terraform state loss. Auto-generated on first deploy — do not edit manually."
  type        = string
  default     = "DO-NOT-EDIT-AUTO-GENERATED"
}


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

variable "enable_jupyterhub" {
  default     = true
  description = "Enable Jupyter Hub"
  type        = bool
}

variable "enable_yunikorn" {
  description = "Enable Apache YuniKorn. Its admission webhook makes it the scheduler of all pods outside kube-system"
  type        = bool
  default     = true
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

variable "enable_nvidia_gpu_operator" {
  description = "Enable NVIDIA GPU Operator addon for GPU workloads with DCGM metrics"
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

variable "eks_pcp_tier" {
  description = <<DESC
EKS Provisioned Control Plane (PCP) scaling tier. Controls the EKS control plane capacity.
Valid values: null (standard/default), "XL", "2XL", "4XL"
- XL  : 1700 API concurrency seats, 167 pods/sec scheduling rate
- 2XL : 3400 API concurrency seats, 283 pods/sec scheduling rate
- 4XL : 6800 API concurrency seats, 400 pods/sec scheduling rate
- 8XL : 13600 API concurrency seats, 400 pods/sec scheduling rate
Leave null to use the default standard tier.
DESC
  type        = string
  default     = null

  validation {
    # contains() fails on a null value. coalesce() changes null to an empty string.
    condition     = var.eks_pcp_tier == null || contains(["XL", "2XL", "4XL", "8XL"], coalesce(var.eks_pcp_tier, ""))
    error_message = "eks_pcp_tier must be null or one of: XL, 2XL, 4XL, 8XL"
  }
}

variable "enable_valkey" {
  description = "Enable Valkey, an in-memory key/value datastore (Redis fork)"
  type        = bool
  default     = false
}

variable "enable_polaris" {
  description = "Enable Apache Polaris (incubating) as an Iceberg REST catalog, with a dedicated S3 warehouse bucket and Trino integration"
  type        = bool
  default     = false
}
