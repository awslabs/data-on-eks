#create local
locals {
  name = "emr-eks-flink-starter"

  region = var.region

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
  flink_team = "flink-team-a"

}
