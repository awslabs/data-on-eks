locals {
  emr_release_label = "emr-7.12.0-flink-k8s-operator-latest"
  emr_flink_operator_values = yamldecode(<<EOT
    # Move ths Part to SET Section
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