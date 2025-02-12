#---------------------------------------------------------------
# RDS Postgres Database for MLflow Backend
#---------------------------------------------------------------
module "db" {
  count   = var.enable_mlflow_tracking ? 1 : 0
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 5.0"

  identifier = local.mlflow_name

  engine               = "postgres"
  engine_version       = "14.13"
  family               = "postgres14"
  major_engine_version = "14"
  instance_class       = "db.m6i.xlarge"

  storage_type      = "io1"
  allocated_storage = 100
  iops              = 3000

  db_name                = local.mlflow_name
  username               = local.mlflow_name
  create_random_password = false
  password               = sensitive(aws_secretsmanager_secret_version.postgres[0].secret_string)
  port                   = 5432

  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group[0].security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period = 5
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_name                  = "mlflow-backend"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "MLflow Postgres Backend for monitoring role"

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  tags = local.tags
}

#---------------------------------------------------------------
# MLflow Postgres Backend DB Master password
#---------------------------------------------------------------
resource "random_password" "postgres" {
  count   = var.enable_mlflow_tracking ? 1 : 0
  length  = 16
  special = false
}
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "postgres" {
  count                   = var.enable_mlflow_tracking ? 1 : 0
  name                    = local.mlflow_name
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "postgres" {
  count         = var.enable_mlflow_tracking ? 1 : 0
  secret_id     = aws_secretsmanager_secret.postgres[0].id
  secret_string = random_password.postgres[0].result
}

#---------------------------------------------------------------
# PostgreSQL RDS security group
#---------------------------------------------------------------
module "security_group" {
  count   = var.enable_mlflow_tracking ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.name
  description = "Complete PostgreSQL example security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = "${module.vpc.vpc_cidr_block},${module.vpc.vpc_secondary_cidr_blocks[0]}"
    },
  ]

  tags = local.tags
}


#---------------------------------------------------------------
# S3 bucket for MLflow artifacts
#---------------------------------------------------------------

#tfsec:ignore:*
module "mlflow_s3_bucket" {
  count   = var.enable_mlflow_tracking ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-artifacts-"

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
# MLflow Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace_v1" "mlflow" {
  count = var.enable_mlflow_tracking ? 1 : 0
  metadata {
    name = local.mlflow_namespace
  }
  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_account_v1" "mlflow" {
  count = var.enable_mlflow_tracking ? 1 : 0
  metadata {
    name        = local.mlflow_service_account
    namespace   = kubernetes_namespace_v1.mlflow[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.mlflow_irsa[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "mlflow" {
  count = var.enable_mlflow_tracking ? 1 : 0
  metadata {
    name      = "${local.mlflow_service_account}-secret"
    namespace = kubernetes_namespace_v1.mlflow[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.mlflow[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.mlflow[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

# Create IAM Role for Service Account (IRSA) Only if MLflow is enabled
module "mlflow_irsa" {
  count = var.enable_mlflow_tracking ? 1 : 0

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  create_policy = false # Policy is created in the next resource

  role_name     = local.mlflow_service_account
  role_policies = { mlflow_policy = aws_iam_policy.mlflow[0].arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = kubernetes_namespace_v1.mlflow[0].metadata[0].name
      service_account = local.mlflow_service_account
    }
  }

  tags = local.tags
}

#--------------------------------------------------------------------------
# IAM policy for MLflow for accessing S3 artifacts and RDS Postgres backend
#--------------------------------------------------------------------------
resource "aws_iam_policy" "mlflow" {
  count = var.enable_mlflow_tracking ? 1 : 0

  description = "IAM policy for MLflow"
  name_prefix = format("%s-%s-", local.name, "mlflow")
  path        = "/"
  policy      = data.aws_iam_policy_document.mlflow[0].json
}

data "aws_iam_policy_document" "mlflow" {
  count = var.enable_mlflow_tracking ? 1 : 0
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${local.partition}:s3:::${module.mlflow_s3_bucket[0].s3_bucket_id}"]

    actions = [
      "s3:ListBucket"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${local.partition}:s3:::${module.mlflow_s3_bucket[0].s3_bucket_id}/*"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${local.partition}:rds-db:${local.region}:${local.account_id}:dbuser:${module.db[0].db_instance_name}/${local.mlflow_name}"]

    actions = [
      "rds-db:connect",
    ]
  }
}
