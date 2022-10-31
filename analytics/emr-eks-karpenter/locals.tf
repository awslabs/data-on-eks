locals {
  name   = var.name
  region = var.region

  vpc_cidr        = var.vpc_cidr
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  core_node_group = "core-node-group"

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })

  kubecost_iam_role_name = format("%s-%s", local.name, "kubecost-irsa")
  kubecost_iam_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.kubecost_iam_role_name}"
}
