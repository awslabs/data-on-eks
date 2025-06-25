variable "vpc_id" {
  type        = string
  description = "ID du VPC parent"
}

variable "natgw_id" {
  type        = string
  description = "ID de la NAT Gateway"
}

variable "cidr_block" {
  type        = string
  description = "CIDR block du subnet Outpost"
}

variable "outpost_arn" {
  type        = string
  description = "ARN de l'Outpost"
}

variable "outpost_az" {
  type        = string
  description = "AZ de l'Outpost"
}

variable "name_prefix" {
  type        = string
  description = "Préfixe de nom pour les ressources"
}

variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}
