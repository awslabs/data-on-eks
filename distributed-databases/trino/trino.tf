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

#---------------------------------------
# Trino Helm Add-on
#---------------------------------------
module "trino_addon" {
  depends_on = [
    module.eks_blueprints_addons,
  ]

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1.1" #ensure to update this to the latest/desired version

  chart            = "trino"
  chart_version    = "0.34.0"
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
        irsa_arn           = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.trino_sa}-role"
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
      provider_arn    = module.eks.oidc_provider_arn
      service_account = local.trino_sa
    }
  }
}


#---------------------------------------------------------------
# KEDA ScaleObject - Trino Prometheus
#---------------------------------------------------------------
resource "kubectl_manifest" "trino_keda" {

  yaml_body = templatefile("${path.module}/trino-keda.yaml", {
    trino_namespace = local.trino_namespace
  })

  depends_on = [
    module.eks_blueprints_addons,
    module.trino_addon
  ]
}
