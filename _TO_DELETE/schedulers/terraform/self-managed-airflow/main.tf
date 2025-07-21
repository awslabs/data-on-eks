provider "aws" {
  region = local.region
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
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)

  airflow_name                      = "airflow"
  airflow_namespace                 = "airflow"
  airflow_scheduler_service_account = "airflow-scheduler"
  airflow_webserver_service_account = "airflow-webserver"
  airflow_workers_service_account   = "airflow-worker"
  airflow_webserver_secret_name     = "airflow-webserver-secret-key"
  efs_storage_class                 = "efs-sc"
  efs_pvc                           = "airflowdags-pvc"
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
