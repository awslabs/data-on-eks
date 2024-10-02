variable "eks_cluster_name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "doeks-aws-batch"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  default     = "us-east-1"
  type        = string
}

variable "num_azs" {
  description = "The number of Availability Zones to deploy subnets to. Must be 2 or more"
  default     = 2
  type        = number
  validation {
    condition     = var.num_azs >= 2
    error_message = "The number of Availability Zones must be 2 or more."
  }
}

variable "eks_cluster_version" {
  description = "EKS Cluster Kubernetes version. AWS Batch recommends version  1.27 and higher."
  type        = string
  default     = "1.30"
}

variable "tags" {
  description = "Default tags"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.1.0.0/16"
}

# Only two Subnets for with low IP range for internet access
variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet"
  type        = list(string)
  default     = ["10.1.255.128/26", "10.1.255.192/26"]
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet"
  type        = list(string)
  default     = ["10.1.0.0/17", "10.1.128.0/18"]
}

variable "eks_public_cluster_endpoint" {
  description = "Whether to have a public cluster endpoint for the EKS cluster.   #WARNING: Avoid a public endpoint in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing."
  type        = bool
  default     = true
}

variable "eks_private_cluster_endpoint" {
  description = "Whether to have a private cluster endpoint for the EKS cluster."
  type        = bool
  default     = true
}

variable "aws_batch_doeks_namespace" {
  description = "The AWS Batch EKS namespace"
  type        = string
  default     = "doeks-aws-batch"
}

variable "aws_batch_doeks_ce_name" {
  description = "The AWS Batch EKS namespace"
  type        = string
  default     = "doeks-CE1"
}

variable "aws_batch_doeks_jq_name" {
  description = "The AWS Batch EKS namespace"
  type        = string
  default     = "doeks-JQ1"
}

variable "aws_batch_doeks_jd_name" {
  description = "The AWS Batch example job definition name"
  type        = string
  default     = "doeks-hello-world"
}

variable "aws_batch_min_vcpus" {
  description = "The minimum aggregate vCPU for AWS Batch compute environment"
  type        = number
  default     = 0
}

variable "aws_batch_max_vcpus" {
  description = "The minimum aggregate vCPU for AWS Batch compute environment"
  type        = number
  default     = 256
}

variable "aws_batch_instance_types" {
  description = "The set of instance types to launch for AWS Batch jobs."
  type        = list(string)
  default     = ["optimal"]
}
