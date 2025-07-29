terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    kustomization = {
      source = "kbst/kustomization"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}