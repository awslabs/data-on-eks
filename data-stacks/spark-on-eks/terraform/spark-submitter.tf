#---------------------------------------------------------------
# Spark REST submitter (operator feature gate RestSubmitter)
# Source and design: submitter/README.md
#---------------------------------------------------------------
locals {
  # The operator sends all job namespaces to the submitter. A namespace that the submitter
  # does not accept fails without a retry, so both lists come from the operator values.
  spark_submitter_job_namespaces = toset(local.spark_operator_values.spark.jobNamespaces)
}

resource "kubectl_manifest" "spark_submitter_namespace" {
  yaml_body = file("${path.module}/manifests/spark-submitter/namespace.yaml")
}

resource "kubectl_manifest" "spark_submitter_service_account" {
  yaml_body = file("${path.module}/manifests/spark-submitter/serviceaccount.yaml")

  depends_on = [kubectl_manifest.spark_submitter_namespace]
}

resource "kubectl_manifest" "spark_submitter_service" {
  yaml_body = file("${path.module}/manifests/spark-submitter/service.yaml")

  depends_on = [kubectl_manifest.spark_submitter_namespace]
}

resource "kubectl_manifest" "spark_submitter_role" {
  for_each = local.spark_submitter_job_namespaces

  yaml_body = templatefile("${path.module}/manifests/spark-submitter/role.yaml", {
    namespace = each.value
  })

  depends_on = [kubectl_manifest.team_namespaces]
}

resource "kubectl_manifest" "spark_submitter_role_binding" {
  for_each = local.spark_submitter_job_namespaces

  yaml_body = templatefile("${path.module}/manifests/spark-submitter/rolebinding.yaml", {
    namespace = each.value
  })

  depends_on = [kubectl_manifest.spark_submitter_role]
}

resource "kubectl_manifest" "spark_submitter" {
  yaml_body = templatefile("${path.module}/manifests/spark-submitter/deployment.yaml", {
    job_namespaces = join(",", sort(local.spark_submitter_job_namespaces))
    enable_ipv6    = var.enable_ipv6
  })

  depends_on = [
    kubectl_manifest.spark_submitter_service_account,
    kubectl_manifest.spark_submitter_service,
    kubectl_manifest.spark_submitter_role_binding,
    kubectl_manifest.karpenter_resources,
  ]
}
