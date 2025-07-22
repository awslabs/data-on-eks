variable "helm_releases" {
  description = "A map of Helm releases to create. This provides the ability to pass in an arbitrary map of Helm chart definitions to create"
  type        = any
  default     = {}
}