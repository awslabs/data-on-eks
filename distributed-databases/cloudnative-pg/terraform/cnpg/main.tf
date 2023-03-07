provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------

module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.23.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.25"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  managed_node_groups = {
    mg_5 = {
      node_group_name = "managed-ondemand"
      instance_types  = ["m5.large"]
      min_size        = 3
      max_size        = 3
      desired_size    = 3
      subnet_ids      = module.vpc.private_subnets
    }
  }

  tags = local.tags
}

resource "helm_release" "example" {
  name             = local.name
  chart            = "cloudnative-pg"
  repository       = "https://cloudnative-pg.github.io/charts"
  version          = "0.17.0"
  namespace        = "${local.name}-system"
  create_namespace = true
  description      = "CloudNativePG Operator Helm chart deployment configuration"
  values           = [templatefile("${path.module}/values.yaml", {})]
}

resource "kubectl_manifest" "demo-namespace" {
  yaml_body = file("../demo-manifests/demo-namespace.yaml")

  depends_on = [helm_release.example]
}

resource "kubectl_manifest" "demo-storageclass" {
  yaml_body = file("../demo-manifests/demo-storageclass.yaml")

  depends_on = [kubectl_manifest.demo-namespace]
}

resource "kubectl_manifest" "demo-cnpg-cluster" {
  yaml_body = file("../demo-manifests/demo-cnpg-cluster.yaml")

  depends_on = [kubectl_manifest.demo-storageclass]
}