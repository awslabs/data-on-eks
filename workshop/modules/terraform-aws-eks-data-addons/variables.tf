variable "oidc_provider_arn" {
  description = "The ARN of the cluster OIDC Provider"
  type        = string
}

#---------------------------------------------------
# SPARK K8S OPERATOR
#---------------------------------------------------
variable "enable_spark_operator" {
  description = "Enable Spark on K8s Operator add-on"
  type        = bool
  default     = false
}

variable "spark_operator_helm_config" {
  description = "Helm configuration for Spark K8s Operator"
  type        = any
  default     = {}
}

#-----------APACHE YUNIKORN ADDON-------------
variable "enable_yunikorn" {
  description = "Enable Apache YuniKorn K8s scheduler add-on"
  type        = bool
  default     = false
}

variable "yunikorn_helm_config" {
  description = "Helm configuration for Apache YuniKorn"
  type        = any
  default     = {}
}

#-----------SPARK HISTORY SERVER ADDON-------------
variable "enable_spark_history_server" {
  description = "Enable Spark History Server add-on"
  type        = bool
  default     = false
}

variable "spark_history_server_helm_config" {
  description = "Helm configuration for Spark History Server"
  type        = any
  default     = {}
}

#-----------PROMETHEUS-------------
variable "enable_prometheus" {
  description = "Enable Community Prometheus add-on"
  type        = bool
  default     = false
}

variable "prometheus_helm_config" {
  description = "Community Prometheus Helm Chart config"
  type        = any
  default     = {}
}

#-----------KUBECOST-------------
variable "enable_kubecost" {
  description = "Enable Kubecost add-on"
  type        = bool
  default     = false
}

variable "kubecost_helm_config" {
  description = "Kubecost Helm Chart config"
  type        = any
  default     = {}
}

#-----------GRAFANA-------------
variable "enable_grafana" {
  description = "Enable Grafana add-on"
  type        = bool
  default     = false
}

variable "grafana_helm_config" {
  description = "Grafana Helm Chart config"
  type        = any
  default     = {}
}

#-----------FLINK OPERATOR-------------
variable "enable_flink_operator" {
  description = "Enable Flink Operator add-on"
  type        = bool
  default     = false
}

variable "flink_operator_helm_config" {
  description = "Flink Operator Helm Chart config"
  type        = any
  default     = {}
}
