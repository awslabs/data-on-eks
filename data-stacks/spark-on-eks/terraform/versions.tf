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

  # Exact versions: upgrade on purpose (change here, then "terraform init -upgrade").
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.68.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.1.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    encode = {
      source  = "justenwalker/encode"
      version = "0.3.0-beta.1"
    }
    # Used only by modules. Root pins keep a fresh clone without a lock file on the same versions.
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.4.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.1"
    }
  }
}
