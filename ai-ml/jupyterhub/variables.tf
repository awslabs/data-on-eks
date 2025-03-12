variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "jupyterhub-on-eks"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.30"
  type        = string
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/21"
  type        = string
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

# NOTE: You need to use private domain or public domain name with ACM certificate
# Data-on-EKS website docs will show you how to create free public domain name with ACM certificate for testing purpose only
# Example of public domain name(<subdomain-name>.<domain-name>.com): eks.jupyter-doeks.dynamic-dns.com
variable "jupyter_hub_auth_mechanism" {
  type        = string
  description = "Allowed values: cognito, dummy, oauth"
  default     = "dummy"
}

#  Domain name is public so make sure you use a unique while deploying, Only needed if auth mechanism is set to cognito
variable "cognito_custom_domain" {
  description = "Cognito domain prefix for Hosted UI authentication endpoints"
  type        = string
  default     = "eks"
}

# Only needed if auth mechanism is set to cognito
variable "acm_certificate_domain" {
  type        = string
  description = "Enter domain name with wildcard and ensure ACM certificate is created for this domain name, e.g. *.example.com"
  default     = ""
}

# Only needed if auth mechanism is set to cognito or oauth. This is the domain for jupyterhub
variable "jupyterhub_domain" {
  type        = string
  description = "Enter domain name for jupyterhub to be hosted,  e.g. eks.example.com. Only needed if auth mechanism is set to cognito or oauth"
  default     = ""
}

# Only needed if auth mechanism is set to oauth. This is the root path for the oidc endpoints
variable "oauth_domain" {
  type        = string
  description = "Enter oauth domain and endpoint, e.g. https://keycloak.example.com/realms/master/protocol/openid-connect. Only needed if auth mechanism is set to oauth"
  default     = ""
}

# Only needed if auth mechanism is set to oauth. This is the id of the client
variable "oauth_jupyter_client_id" {
  type        = string
  description = "Enter oauth client id for jupyterhub, e.g. jupyterhub. Only needed if auth mechanism is set to oauth"
  default     = ""
}

# Only needed if auth mechanism is set to oauth. This is the secret for the client
variable "oauth_jupyter_client_secret" {
  type        = string
  description = "Enter oauth client secret. Only needed if auth mechanism is set to oauth"
  default     = ""
  sensitive   = true
}

# Only needed if auth mechanism is set to oauth. This is the key to use for looking up the username.
variable "oauth_username_key" {
  type        = string
  description = "oauth field for the username. e.g. 'preferred_username' Only needed if auth mechanism is set to oauth"
  default     = ""
}
