locals {
  spark_history_server_name            = "spark-history-server"
  spark_history_server_service_account = "spark-history-server-sa"

  spark_history_server_values = yamldecode(templatefile("${path.module}/helm-values/spark-history-server.yaml",
    {
      s3_bucket_name            = module.s3_bucket.s3_bucket_id,
      event_log_prefix          = aws_s3_object.this.key,
      spark_history_server_role = module.spark_history_server_irsa.arn
    })
  )
}


resource "kubectl_manifest" "spark_history_server" {
  yaml_body = templatefile("${path.module}/argocd-applications/spark-history-server.yaml", {
    # The indent must match the position of helm.valuesObject in the template.
    user_values_yaml = indent(8, yamlencode(local.spark_history_server_values))
  })

  depends_on = [
    helm_release.argocd,
    module.spark_history_server_irsa,
  ]
}


# The Spark History Server image uses Java SDK 1.x, which does not support Pod Identity. Thus it uses IRSA.

module "spark_history_server_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.8.2"
  name    = "${module.eks.cluster_name}-shs"

  policies = {
    policy = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Change this policy for the access that you need.
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.spark_history_server_name}:${local.spark_history_server_service_account}"]
    }
  }
}
