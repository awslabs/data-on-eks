data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "mwaa_emrjob" {
  statement {
    actions = [
      "emr-containers:StartJobRun",
      "emr-containers:ListJobRuns",
      "emr-containers:DescribeJobRun",
      "emr-containers:CancelJobRun"
    ]
    resources = ["*"]
    effect    = "Allow"
  }

}
