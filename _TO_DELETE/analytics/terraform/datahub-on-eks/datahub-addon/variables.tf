variable "datahub_helm_config" {
  description = "Datahub Helm Chart config"
  type        = any
  default     = {}
}

variable "prereq_helm_config" {
  description = "Datahub PreReq Helm Chart config"
  type        = any
  default     = {}
}

variable "prefix" {
  description = "local name"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "vpc id"
  type        = string
  default     = ""
}

variable "vpc_private_subnets" {
  description = "vpc private subnets"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "Cidr range for security group rules"
  type        = string
  default     = ""
}
