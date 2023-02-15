locals {
  name   = var.name
  region = var.region

  vpc_cidr      = var.vpc_cidr
  azs           = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_endpoints = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })

  emr_on_eks_teams = {
    emr-data-team-a = {
      namespace               = "emr-data-team-a"
      job_execution_role      = "emr-eks-data-team-a"
      additional_iam_policies = [aws_iam_policy.emr_data_team_a.arn]
    },
    emr-data-team-b = {
      namespace               = "emr-data-team-b"
      job_execution_role      = "emr-eks-data-team-b"
      additional_iam_policies = [aws_iam_policy.emr_data_team_b.arn]
    }
  }
}
