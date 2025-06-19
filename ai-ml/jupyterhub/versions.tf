terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.72"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0" # Replace with the appropriate version of the random provider
    }

    archive = {
      source  = "hashicorp/archive"
      version = "2.4.0"
    }
  }
}
