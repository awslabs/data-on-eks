
variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}

variable "cluster_issuer_name" {
    description = "Name of the ClusterIssuer for cert-manager"
    type        = string
}

variable "dns_name" {
    description = "DNS name"
    type        = string
}

variable "namespace" {
    description = "Namespace for gateway resources"
    type        = string
}

variable "virtual_service_name" {
    description = "Name of the virtual service"
    type        = string
}

variable "service_name" {
    description = "Name of the service to be exposed"
    type        = string
}

variable "service_port" {
    description = "Port of the service to be exposed"
    type        = number
}