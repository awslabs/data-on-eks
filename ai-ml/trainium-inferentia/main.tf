provider "aws" {
  region = local.region
}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
provider "kubectl" {
  apply_retry_count      = 30
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

resource "random_string" "this" {
  length  = 5
  special = false
  upper   = false
  lower   = true
  numeric  = true
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

/* data "external" "eks_azs" {
  program = ["bash", "${path.module}/get_eks_azs.sh", var.region]
}

locals {
  name   = "${var.name}-${random_string.this.result}"
  region = var.region
  azs    = [data.external.eks_azs.result["EKSAZ1"], data.external.eks_azs.result["EKSAZ2"]]
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
} */

locals {
  az_mapping = {
    "us-west-2" = ["usw2-az4", "usw2-az1"],
    "us-east-1" = ["use1-az6", "use1-az5"],
    "us-east-2" = ["use2-az3", "use2-az1"]
  }

  name   = "${var.name}-${random_string.this.result}"
  region = var.region
  azs    = local.az_mapping[var.region]  # Retrieves the AZs from the mapping based on the specified region
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}


