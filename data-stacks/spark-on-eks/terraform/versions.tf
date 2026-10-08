terraform {
  required_version = ">= 1.10.0"

  # Remote state in S3. The bucket is not managed by this configuration.
  backend "s3" {
    bucket       = "eks-data-workload-tests"
    key          = "spark-on-eks/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    encode = {
      source  = "justenwalker/encode"
      version = "0.3.0-beta.1"
    }
  }
}
