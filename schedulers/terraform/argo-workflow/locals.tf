locals {
  name                       = var.name
  region                     = var.region
  azs                        = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_endpoints              = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]
  amp_ingest_service_account = "amp-iamproxy-ingest-service-account"
  namespace                  = "prometheus"
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
