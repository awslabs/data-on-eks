#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region

  vpc_cidr           = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  k8ssandra_operator_name = "k8ssandra-operator"
  
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }

  csi_name        = "aws-ebs-csi-driver"
  csi_namespace   = "kube-system"
}
