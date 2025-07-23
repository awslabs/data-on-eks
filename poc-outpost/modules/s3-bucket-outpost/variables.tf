variable "vpc-id" {
  type        = string
  description = "Id du VPC"
}

variable "outpost_name" {
  type        = string
  description = "Nom de l'Outpost"
}

variable "bucket_name" {
  type        = string
  description = "Nom du bucket S3 à créer sur l'Outpost"
}

variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}

# Depuis module.outpost_subnet.subnet_id[0]
variable "output_subnet_id" {
  type        = string
  description = "Subnet ID for outpost"
}

# vpc id
variable "vpc_id" {
  type        = string
  description = "Id du VPC"
}