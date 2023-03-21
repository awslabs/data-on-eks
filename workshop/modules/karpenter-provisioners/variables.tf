variable "name" {
  description = "Name of the EKS Cluster"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}
