locals {
  flink_team              = "flink-team-a"
  flink_operator          = "flink-kubernetes-operator"
  emr_release_label       = "emr-7.1.0-flink-k8s-operator-latest"
  flink_operator_values   = yamldecode(<<EOT
    # Move ths Part to SET Section
operatorExecutionRoleArn: ${module.flink_irsa_operator.iam_role_arn}
emrContainers:
  awsRegion: ${local.region}
  emrReleaseLabel: ${local.emr_release_label}

EOT
    )
}

resource "kubectl_manifest" "flink_operator" {
  yaml_body = templatefile("${path.module}/flink-operator.yaml", {
    user_values_yaml = indent(10, yamlencode(local.flink_operator_values))
  })

  depends_on = [
    helm_release.argocd
  ]
}
