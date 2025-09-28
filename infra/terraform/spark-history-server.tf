locals {
  spark_history_server_name            = "spark-history-server"
  spark_history_server_service_account = "spark-history-server-sa"

  spark_history_server_values = var.enable_spark_history_server ? yamldecode(templatefile("${path.module}/helm-values/spark-history-server.yaml",
    {
      s3_bucket_name            = module.s3_bucket.s3_bucket_id,
      event_log_prefix          = aws_s3_object.this.key,
      spark_history_server_role = "${module.spark_history_server_irsa[0].iam_role_arn}"
    })
    ) : {
    historyServer = {}
    logStore      = {}
  }
}


#---------------------------------------------------------------
# Spark History Server Application
#---------------------------------------------------------------
resource "kubectl_manifest" "spark_history_server" {
  count = var.enable_spark_history_server ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/spark-history-server.yaml", {
    # Place under `helm.valuesObject:` at 8 spaces (adjust if your template indent differs)
    user_values_yaml = indent(8, yamlencode(local.spark_history_server_values))
  })

  depends_on = [
    helm_release.argocd,
    module.spark_history_server_irsa,
  ]
}


# we need to use IRSA because spark history server image does not support pod identity yet (java sdk 1.x)
#---------------------------------------------------------------
# IRSA for Spark History Server
#---------------------------------------------------------------

module "spark_history_server_irsa" {
  count     = var.enable_spark_history_server ? 1 : 0
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.52"
  role_name = "${module.eks.cluster_name}-spark-history-server"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Policy needs to be defined based in what you need to give access to your notebook instances.
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.spark_history_server_name}:${local.spark_history_server_service_account}"]
    }
  }
}
