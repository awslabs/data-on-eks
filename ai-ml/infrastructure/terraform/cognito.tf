#---------------------------------------------------------------
# Lambda function for pre token generation
#----------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "cognito-idp.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy" "lambda_execution_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "iam_for_lambda" {
  count              = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  count      = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  role       = aws_iam_role.iam_for_lambda[0].name
  policy_arn = data.aws_iam_policy.lambda_execution_policy.arn
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "/tmp/lambda.zip"
  source {
    filename = "index.mjs"
    content  = <<-EOF
    export const handler = async (event) => {
        event.response = {
          claimsOverrideDetails: {
            claimsToAddOrOverride: {
              department: "engineering",
            },
          },
        };

        return event;
    };

    EOF
  }
}

resource "aws_lambda_function" "pretoken_trigger" {
  count            = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  function_name    = "pretoken-trigger-function"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = "nodejs18.x"
  handler = "index.handler"

  role = aws_iam_role.iam_for_lambda[0].arn
}

#---------------------------------------------------------------
# Cognito pool, domain and client creation.
# This can be used
# Auth integration later.
#----------------------------------------------------------------
resource "aws_cognito_user_pool" "pool" {
  count = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  name  = "jupyterhub-userpool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
  }

  lambda_config {
    pre_token_generation = aws_lambda_function.pretoken_trigger[0].arn
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  count        = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  domain       = local.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.pool[0].id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  count                 = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  name                  = "jupyter-client"
  access_token_validity = 1
  token_validity_units {
    access_token = "days"
  }
  callback_urls                        = ["https://${var.jupyterhub_domain}/hub/oauth_callback"]
  user_pool_id                         = aws_cognito_user_pool.pool[0].id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  generate_secret                      = true
  supported_identity_providers = [
    "COGNITO"
  ]

  depends_on = [aws_cognito_user_pool_domain.domain]
}

#---------------------------------------------------------------
# Cognito identity pool creation.
#----------------------------------------------------------------
resource "aws_cognito_identity_pool" "identity_pool" {
  count                            = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  identity_pool_name               = "jupyterhub-identity-pool"
  allow_unauthenticated_identities = false
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.user_pool_client[0].id
    provider_name           = aws_cognito_user_pool.pool[0].endpoint
    server_side_token_check = true
  }

  depends_on = [aws_cognito_user_pool_client.user_pool_client]
}

resource "aws_s3_bucket" "jupyterhub_bucket" {
  count         = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  bucket_prefix = "jupyterhub-test-bucket-"
}

resource "aws_s3_object" "engineering_object" {
  count  = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  bucket = aws_s3_bucket.jupyterhub_bucket[0].id
  key    = "engineering/"
}

resource "aws_s3_object" "legal_object" {
  count  = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  bucket = aws_s3_bucket.jupyterhub_bucket[0].id
  key    = "legal/"
}

#---------------------------------------------------------------
# IAM role for a team member from the engineering department
# In theory there would be other departments such as "legal"
#----------------------------------------------------------------
resource "aws_iam_role" "cognito_authenticated_engineering_role" {
  count = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0

  name = "EngineeringTeamRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"],
        Effect = "Allow",
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        },
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.identity_pool[0].id
          },
          "ForAnyValue:StringLike" : {
            "cognito-identity.amazonaws.com:amr" : "authenticated"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_cognito_engineering_policy" {
  count = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  name  = "s3_cognito_engineering_policy"
  role  = aws_iam_role.cognito_authenticated_engineering_role[0].id

  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:List*"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "s3:prefix": "$${aws:PrincipalTag/department}"
        }
      }
    }
  ]
}
EOF
}

resource "aws_cognito_identity_pool_provider_principal_tag" "example" {
  count                  = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  identity_pool_id       = aws_cognito_identity_pool.identity_pool[0].id
  identity_provider_name = aws_cognito_user_pool.pool[0].endpoint
  use_defaults           = false
  principal_tags = {
    department = "department"
  }
}

resource "aws_iam_policy_attachment" "s3_readonly_policy_attachment" {
  count      = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  name       = "S3ReadOnlyAccessAttachment"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  roles      = [aws_iam_role.cognito_authenticated_engineering_role[0].name]
}

resource "aws_cognito_identity_pool_roles_attachment" "identity_pool_roles" {
  count            = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  identity_pool_id = aws_cognito_identity_pool.identity_pool[0].id
  roles = {
    authenticated = aws_iam_role.cognito_authenticated_engineering_role[0].arn
  }
}
