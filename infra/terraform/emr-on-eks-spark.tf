#---------------------------------------------------------------
# EMR on EKS - Spark Virtual Clusters and Spark Operator
# Creates EMR virtual clusters for running Spark jobs on EKS
# Optionally deploys EMR Spark Operator for declarative job management
#---------------------------------------------------------------

locals {
  emr_teams = var.enable_emr_on_eks ? {
    emr-data-team-a = {
      namespace = "emr-data-team-a"
    }
    emr-data-team-b = {
      namespace = "emr-data-team-b"
    }
  } : {}

  emr_spark_operator_values = yamldecode(templatefile("${path.module}/helm-values/emr-spark-operator-values.yaml", {
    aws_region = local.region
  }))
}

#---------------------------------------------------------------
# EMR Virtual Cluster Module (KubedAI)
# Creates: namespaces, IAM roles (via Pod Identity), CloudWatch log groups,
# Kubernetes RBAC, and EMR virtual clusters
# Source: https://github.com/KubedAI/terraform-aws-emr-containers
#---------------------------------------------------------------
module "emr_containers" {
  source = "git::https://github.com/KubedAI/terraform-aws-emr-containers.git?ref=v0.2.1"

  count = var.enable_emr_on_eks ? 1 : 0

  eks_cluster_name = module.eks.cluster_name

  # Teams: each entry creates a namespace, IAM role (via Pod Identity), CloudWatch log group,
  # and EMR virtual cluster scoped to that namespace
  teams = {
    for team_name, team_config in local.emr_teams : team_name => {
      namespace                      = team_config.namespace
      create_namespace               = true
      create_emr_rbac                = false
      create_iam_role                = true
      iam_role_name                  = "${local.name}-${team_name}"
      s3_bucket_arns                 = [module.s3_bucket.s3_bucket_arn, "${module.s3_bucket.s3_bucket_arn}/*"]
      additional_iam_policy_arns     = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
      create_cloudwatch_log_group    = true
      cloudwatch_log_group_name      = "/emr-on-eks-logs/${local.name}/${team_name}"
      cloudwatch_log_group_retention = 7
      tags = {
        Name = team_name
        Team = team_name
      }
    }
  }

  tags = local.tags

  # Ensure EKS cluster and core addons are ready before creating EMR resources
  depends_on = [
    module.eks,
    helm_release.argocd,
    aws_eks_addon.aws_ebs_csi_driver
  ]
}

#---------------------------------------------------------------
# EMR Spark Operator
# Deploys AWS EMR Spark Operator for declarative Spark job management
# Note: This is different from the open-source Kubeflow Spark Operator
# Deployed via ArgoCD using public ECR image: public.ecr.aws/emr-on-eks/spark-operator:7.12.0
# Docs: https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/spark-operator-gs.html
#---------------------------------------------------------------

# Deploy EMR Spark Operator via ArgoCD
resource "kubectl_manifest" "emr_spark_operator_application" {
  count = var.enable_emr_spark_operator ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/emr-spark-operator.yaml", {
    user_values_yaml = indent(10, yamlencode(local.emr_spark_operator_values))
  })

  depends_on = [
    helm_release.argocd
  ]
}
