#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region

  vpc_cidr           = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  k8ssandra_operator_name = "k8ssandra-operator"
  vpc_endpoints      = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

  csi_name        = "aws-ebs-csi-driver"
  csi_create_irsa = true
  csi_namespace   = "kube-system"

  # k8ssandra_operator_helm_config = {
  #   name             = local.name
  #   chart            = "k8ssandra-operator"
  #   repository       = "https://helm.k8ssandra.io/stable"
  #   version          = "0.39.1"
  #   namespace        = local.name
  #   create_namespace = true
  #   values           = [templatefile("${path.module}/helm-values/values.yaml", {})]
  #   description      = "K8ssandra Operator to run Cassandra DB on Kubernetes"
  # }
  # helm_config = merge(local.k8ssandra_operator_helm_config, var.k8ssandra_helm_config)

}
