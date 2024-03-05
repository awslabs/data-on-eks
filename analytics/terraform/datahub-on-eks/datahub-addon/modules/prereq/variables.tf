variable "prefix" {
  description = "local name"
  type        = string
  default     = "doeks"
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
