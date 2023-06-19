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

variable "create_iam_service_linked_role_es" {
  type        = bool
  default     = true
  description = "Whether to create `AWSServiceRoleForAmazonOpensearchService` service-linked role. Set it to `false` if the role already exists"
}
