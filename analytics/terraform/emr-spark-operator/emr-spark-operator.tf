resource "helm_release" "emr_spark_operator" {
  name = "spark-operator"

  repository = "oci://895885662937.dkr.ecr.us-west-2.amazonaws.com"
  chart      = "spark-operator"

  version = "1.1.26-amzn-0"

  namespace = "spark-operator"

  create_namespace = true

  repository_username = data.aws_ecr_authorization_token.token.user_name
  repository_password = data.aws_ecr_authorization_token.token.password

  values = [
    file("${path.module}/helm-values/emr-spark-operator-values.yaml")
  ]
}
