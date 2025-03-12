terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.72"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}
