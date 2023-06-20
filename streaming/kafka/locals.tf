#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region

  vpc_cidr           = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  strimzi_kafka_name = "strimzi-kafka-operator"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }

  csi_name        = "aws-ebs-csi-driver"
  csi_create_irsa = true
  csi_namespace   = "kube-system"
}
