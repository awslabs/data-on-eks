resource "aws_cognito_user_pool_client" "trino" {
  name                   = "trino-client"
  user_pool_id           = local.cognito_user_pool_id
  generate_secret        = true
  allowed_oauth_flows    = ["code"]
  allowed_oauth_scopes   = ["openid", "email"]
  callback_urls          = ["https://k8s-trino-6ae964ff84-341795026.us-west-2.elb.amazonaws.com/oidc-callback"]
  allowed_oauth_flows_user_pool_client = true
}

resource "kubectl_manifest" "trino_cert" {

  yaml_body = templatefile("${path.module}/helm-values/certificate.yaml", {
    cluster_issuer_name = local.cluster_issuer_name
    trino_name_cert = "${local.trino_name}-cert"
    trino_namespace = "${local.trino_namespace}"
    trino_name_tls = "${local.trino_name}-tls"
  })

}

# resource "aws_cognito_user_pool_client" "airflow" {
#   name                   = "airflow-client"
#   user_pool_id           = local.cognito_user_pool_id
#   generate_secret        = false
#   allowed_oauth_flows    = ["code"]
#   allowed_oauth_scopes   = ["openid", "email"]
#   callback_urls          = ["https://airflow.example.com/oauth2/callback"]
#   allowed_oauth_flows_user_pool_client = true
# }