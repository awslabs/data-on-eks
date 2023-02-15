locals {
  name   = var.name
  region = var.region

  vpc_cidr      = var.vpc_cidr
  azs           = slice(data.aws_availability_zones.available.names, 0, 3)
  dag_s3_path   = "dags"
  vpc_endpoints = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
