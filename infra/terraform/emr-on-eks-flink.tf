locals {
  emr_release_label = "emr-7.12.0-flink-k8s-operator-latest"
  emr_role_names = {
    for k, v in local.emr_teams : k => "${local.name}-${k}" if var.enable_emr_flink_operator
  }

  emr_team_names = {
    for k, v in local.emr_teams : k => {
      team_key  = "${k}"
      namespace = "${v.namespace}"
    } if var.enable_emr_flink_operator
  }

  emr_flink_operator_values = yamldecode(<<EOT
    # Move this Part to SET Section
emrContainers:
  awsRegion: ${local.region}
  emrReleaseLabel: ${local.emr_release_label}
EOT
  )
}

#---------------------------------------------------------------
# EMR Flink Kubernetes Operator
# Deploys AWS EMR Flink Kubernetes Operator
# Note: This is different from the open-source Flink Kubernetes Operator
# Deployed via ArgoCD using public ECR image: public.ecr.aws/emr-on-eks/spark-operator:7.12.0
#---------------------------------------------------------------

resource "kubectl_manifest" "emr_flink_operator" {
  count = var.enable_emr_flink_operator ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/emr-flink-operator.yaml", {
    user_values_yaml = indent(10, yamlencode(local.emr_flink_operator_values))
  })

  depends_on = [
    helm_release.argocd
  ]
}



data "encode_base36" "team_role_name" {
  for_each = local.emr_role_names

  value     = each.value
  lowercase = true
}

resource "aws_eks_pod_identity_association" "jobmanager" {
  for_each = local.emr_team_names

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = "emr-containers-sa-flink-jobmanager-${data.aws_caller_identity.current.account_id}-${data.encode_base36.team_role_name[each.value.team_key].result}"
  role_arn        = module.emr_containers[0].job_execution_role_arns[each.value.team_key]

}

resource "aws_eks_pod_identity_association" "taskmanager" {
  for_each = local.emr_team_names

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = "emr-containers-sa-flink-taskmanager-${data.aws_caller_identity.current.account_id}-${data.encode_base36.team_role_name[each.value.team_key].result}"
  role_arn        = module.emr_containers[0].job_execution_role_arns[each.value.team_key]

}
