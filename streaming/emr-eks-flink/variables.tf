#create a variable
variable "eks_cluster_version" {
  type    = string
  default = "1.28"
}
variable "region" {
  type    = string
  default = "us-west-2"
}

