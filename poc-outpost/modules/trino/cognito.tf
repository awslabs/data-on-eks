resource "aws_cognito_user_pool_client" "trino" {
  name                   = "trino-client"
  user_pool_id           = local.cognito_user_pool_id
  generate_secret        = true
  allowed_oauth_flows    = ["code"]
  allowed_oauth_scopes   = ["openid", "email"]
  callback_urls          = ["https://${local.trino_name}.${local.main_domain}/oidc-callback"]
  allowed_oauth_flows_user_pool_client = true
}

# resource "kubectl_manifest" "trino_cert" {
#
#   yaml_body = templatefile("${path.module}/helm-values/certificate.yaml", {
#     cluster_issuer_name = local.cluster_issuer_name
#     trino_namespace = local.trino_namespace
#     wildcard_domain = local.main_domain
#     trino_wildcard-eks-tls_name = local.wildcard_domain_secret_name
#   })
#
# }

# resource "aws_cognito_user_pool_client" "airflow" {
#   name                   = "airflow-client"
#   user_pool_id           = local.cognito_user_pool_id
#   generate_secret        = false
#   allowed_oauth_flows    = ["code"]
#   allowed_oauth_scopes   = ["openid", "email"]
#   callback_urls          = ["https://airflow.example.com/oauth2/callback"]
#   allowed_oauth_flows_user_pool_client = true
# }