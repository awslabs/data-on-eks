locals {
  name   = var.name
  region = var.region

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })

  spark_team    = "spark-team-a"

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

  kubecost_iam_role_name = format("%s-%s", local.name, "kubecost-irsa")
  kubecost_iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.kubecost_iam_role_name}"
}