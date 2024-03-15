#create local 
locals {
  name                      = "emr-eks-flink-starter"
  service_account_namespace = "kube-system"
  service_account_name      = "aws-load-balancer-controller"

  karpenter_iam_role_name = format("%s-%s", "karpenter", local.name)
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
  flink_team = "flink-team-a"
  region = "us-west-2"
}