variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "datahub-on-eks"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.31"
  type        = string
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}

variable "create_vpc" {
  description = "Create VPC"
  default     = true
  type        = bool
}

variable "vpc_id" {
  description = "VPC Id for the existing vpc - needed when create_vpc set to false"
  default     = ""
  type        = string
}

variable "private_subnet_ids" {
  description = "Ids for existing private subnets - needed when create_vpc set to false"
  default     = []
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR - must change to match the cidr of the existing VPC if create_vpc set to false"
  default     = "10.1.0.0/16"
  type        = string
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  default     = false
  type        = bool
}

# Only two Subnets for with low IP range for internet access
variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet"
  default     = ["10.1.255.128/26", "10.1.255.192/26"]
  type        = list(string)
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet"
  default     = ["10.1.0.0/17", "10.1.128.0/18"]
  type        = list(string)
}
