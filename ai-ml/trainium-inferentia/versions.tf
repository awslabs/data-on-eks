terraform {
  required_version = ">= 1.3.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.61"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.4.1"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.3"
    }
  }

  # ##  Used for end-to-end testing on project; update to suit your needs
  # backend "s3" {
  #   bucket = "doeks-github-actions-e2e-test-state"
  #   region = "us-west-2"
  #   key    = "e2e/trainium-inferentia/terraform.tfstate"
  # }
}
