resource "kubernetes_namespace" "trino" {
  metadata {
    name = "${local.trino_namespace}"
  }
}

resource "random_password" "trino_password" {
  length  = 16
  special = true
}

resource "random_password" "trino_communication_encryption" {
  length  = 16
  special = false
}

resource "bcrypt_hash" "trino_bcrypt" {
  cleartext = random_password.trino_password.result
  cost     = 10
}

data "aws_iam_policy_document" "trino_exchange_access" {
  statement {
    sid    = ""
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${module.trino_exchange_bucket.s3_bucket_id}",
      "arn:aws:s3:::${module.trino_exchange_bucket.s3_bucket_id}/*"
    ]
    actions = ["s3:Get*",
      "s3:List*",
      "s3:*Object*"]
  }
}

data "aws_iam_policy_document" "trino_s3_access" {
  statement {
    sid    = ""
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${module.trino_s3_bucket.s3_bucket_id}",
      "arn:aws:s3:::${module.trino_s3_bucket.s3_bucket_id}/*"
    ]
    actions = ["s3:Get*",
      "s3:List*",
      "s3:*Object*"]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "s3:ListStorageLensConfigurations",
      "s3:ListAccessPointsForObjectLambda",
      "s3:GetAccessPoint",
      "s3:GetAccountPublicAccessBlock",
      "s3:ListAllMyBuckets",
      "s3:ListAccessPoints",
      "s3:ListJobs",
      "s3:PutStorageLensConfiguration",
      "s3:ListMultiRegionAccessPoints",
      "s3:CreateJob"
    ]
  }
}

data "aws_iam_policy" "glue_full_access" {
  arn = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
}

#---------------------------------------------------------------
# Creating an s3 bucket for event logs
#---------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-trino-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Trino S3 Bucket for Data
#---------------------------------------------------------------
module "trino_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "trino-data-bucket-"

  # For example only - please evaluate for your environment
  force_destroy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Creates IAM policy for accessing s3 bucket
#---------------------------------------------------------------
resource "aws_iam_policy" "trino_s3_bucket_policy" {
  description = "IAM role policy for Trino to access the S3 Bucket"
  name        = "${local.name}-s3-irsa-policy"
  policy      = data.aws_iam_policy_document.trino_s3_access.json
}

#---------------------------------------------------------------
# Trino Exchange Manager S3 Bucket
#---------------------------------------------------------------
module "trino_exchange_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "trino-exchange-bucket-"

  # For example only - please evaluate for your environment
  force_destroy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Creates IAM policy for accessing exchange bucket
#---------------------------------------------------------------
resource "aws_iam_policy" "trino_exchange_bucket_policy" {
  description = "IAM role policy for Trino to access the S3 Bucket"
  name        = "${local.name}-exchange-bucket-policy"
  policy      = data.aws_iam_policy_document.trino_exchange_access.json
}

##
# Trino certificat pour la partie HTTPS
##
resource "kubectl_manifest" "trino_cert" {

  yaml_body = templatefile("${path.module}/helm-values/certificate.yaml", {
    cluster_issuer_name = local.cluster_issuer_name
    trino_namespace = local.trino_namespace
    domain = "${local.trino_name}.${local.main_domain}"
    trino_tls = local.trino_tls
  })

}

resource "random_password" "trino_jks_keystore_password" {
  length  = 24
  special = false
}


#---------------------------------------
#Trino Helm Add-on
#---------------------------------------
module "trino_addon" {

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1.1" #ensure to update this to the latest/desired version

  chart            = "trino"
  chart_version    = "1.39.1"
  repository       = "https://trinodb.github.io/charts"
  description      = "Trino Helm Chart deployment"
  namespace        = local.trino_namespace
  create_namespace = true

  values = [
    templatefile("${path.module}/helm-values/trino.yaml",
      {
        sa                 = local.trino_sa
        region             = local.region
        bucket_id          = module.trino_s3_bucket.s3_bucket_id
        exchange_bucket_id = module.trino_exchange_bucket.s3_bucket_id
        default_node_group_type = local.default_node_group_type

        trino_db_password = try(sensitive(aws_secretsmanager_secret_version.postgres.secret_string), "")
        trino_db_user = try(module.db.db_instance_name, "")
        trino_db_url = try(
          "jdbc:postgresql://${module.db.db_instance_endpoint}/${local.trino_name}",
          ""
        )

        irsa_arn           = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.trino_sa}-role"

        #Conf Cognito
        cognito_user_pool_id = local.cognito_user_pool_id
        cognito_user_pool_domain = local.cognito_custom_domain

        cpgnito_user_pool_client_id = try(aws_cognito_user_pool_client.trino.id, "")
        cognito_user_pool_client_secret = try(sensitive(aws_cognito_user_pool_client.trino.client_secret),"")
        cluster_issuer_name = local.cluster_issuer_name

        trino_name = local.trino_name
        trino_domain = "${local.trino_name}.${local.main_domain}"
        trino_tls = local.trino_tls
        trino_user_password = replace(bcrypt_hash.trino_bcrypt.id, "^\\$2[ab]\\$", "$2y$") #trino accepte que les bcrypt avec $2y$
        trino_communication_encryption = random_password.trino_communication_encryption.result # test
        # JKS Keystore
        trino_jks_keystore_password = "TRINOPassword123456!" # test
        #random_password.trino_jks_keystore_password.result

      })
  ]

  set_irsa_names = ["serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"]

  # IAM role for service account (IRSA)
  allow_self_assume_role = true
  create_role            = true
  role_name              = "${local.trino_sa}-role"
  role_name_use_prefix   = false
  role_policies = {
    data_bucket_policy     = aws_iam_policy.trino_s3_bucket_policy.arn
    exchange_bucket_policy = aws_iam_policy.trino_exchange_bucket_policy.arn
    glue_policy            = data.aws_iam_policy.glue_full_access.arn,
  }

  oidc_providers = {
    this = {
      provider_arn    = local.oidc_provider_arn
      service_account = local.trino_sa
    }
  }

  depends_on = [module.db,
    random_password.trino_jks_keystore_password]
}


#---------------------------------------------------------------
# KEDA ScaleObject - Trino Prometheus
#---------------------------------------------------------------
resource "kubectl_manifest" "trino_keda" {

  yaml_body = templatefile("${path.module}/helm-values/trino-keda.yaml", {
    trino_namespace = local.trino_namespace

  })

  depends_on = [
    module.trino_addon
  ]
}

#---------------------------------------------------------------
# Trino Vitual Service qui remplace l'Ingress
#---------------------------------------------------------------

module "trino_virtual_service" {
  source = "../virtualService"

  cluster_issuer_name = var.cluster_issuer_name
  virtual_service_name = local.trino_name
  dns_name = "${local.trino_name}.${local.main_domain}"
  service_name = local.trino_name
  service_port = 8080
  namespace = local.trino_namespace

  tags = local.tags

  depends_on = [module.trino_addon]
}




