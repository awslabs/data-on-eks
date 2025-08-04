variable "kubeflow_domain" {
  type        = string
  description = "Domain kubeflow"
  default = "kubeflow-otl4.orange-eks.com"
}

variable "keycloak_domain" {
  type        = string
  description = "Domain kyecloak"
  default     = "keycloak-otl4.orange-eks.com"
}

variable "keycloak_realm" {
  type        = string
  description = "Realm keycloak"
  default = "dex"
}

variable "dex_client_id" {
  type        = string
  description = "Id client Dex"
  default  = "dex"
}

variable "dex_client_secret" {
  type        = string
  description = "Secret client dex"
}