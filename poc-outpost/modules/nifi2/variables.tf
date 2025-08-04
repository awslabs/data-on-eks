variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}


variable "region" {
  type        = string
  description = "Region AWS cible"
}

variable "eks_cluster_name" {
  type        = string
  description = "Cluster EKS Cible"
}

variable "cluster_name" {
  type        = string
  description = "Nom du cluster nifi"
  default= "simple-nifi"
}

variable "replica" {
  type        = number
  description = "Nombre d'instance dans le cluster nifi"
  default= 2
}

variable "external_dns_name" {
  type        = string
  description = "External DNS Name"
  default = "nifi2.orange-eks.com"
}

variable "nifi_namespace" {
  type        = string
  description = "Namespace"
  default = "nifi2"
}

variable "keycloak_url" {
  type        = string
  description = "Url keycloak"
}

variable "client_keycloak" {
  type        = string
  description = "Client keycloak"
}

variable "secret_keycloak" {
  type        = string
  description = "Secret keycloak"
}