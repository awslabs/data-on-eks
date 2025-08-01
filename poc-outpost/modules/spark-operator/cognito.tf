resource "aws_cognito_user_pool_client" "shs" {
  name                   = "shs-client"
  user_pool_id           = local.cognito_user_pool_id
  generate_secret        = true
  allowed_oauth_flows    = ["code"]
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_scopes   = ["openid", "email"]
  callback_urls          = ["https://${local.spark_history_server_name}.${local.main_domain}/callback"]
  allowed_oauth_flows_user_pool_client = true

  access_token_validity  = 60     # minutes
  id_token_validity      = 60     # minutes
  refresh_token_validity = 30     # days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "helm_release" "oauth2_proxy" {
  name             = "oauth2-proxy"
  namespace        = local.spark_history_server_namespace
  create_namespace = true
  repository       = "https://oauth2-proxy.github.io/manifests"
  chart            = "oauth2-proxy"
  version          = "7.15.0"

  values = [
    yamlencode({
      configFile = null

      config = {
        clientID       = aws_cognito_user_pool_client.shs.id
        clientSecret   = aws_cognito_user_pool_client.shs.client_secret
        cookieSecret   = base64encode(random_password.cookie_secret.result)
        cookieSecure   = true
        provider       = "oidc"
        oidcIssuerURL  = "https://cognito-idp.us-west-2.amazonaws.com/us-west-2_Qat2OJT3w"
        redirectURL    = "https://${local.spark_history_server_name}.${local.main_domain}/callback"
        emailDomains   = ["*"]
        upstreams      = [
          "http://spark-history-server.spark-history-server.svc.cluster.local:80"
        ]
      }
      service = {
        type = "ClusterIP"
      }
    })
  ]
}

resource "random_password" "cookie_secret" {
  length  = 16
  special = false
}