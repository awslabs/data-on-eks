#---------------------------------------------------------------
# using existing private subnets for Airflow on outpost
#---------------------------------------------------------------
resource "aws_db_subnet_group" "private" {
  name       = "${local.airflow_name}-db-private"
  subnet_ids = module.outpost_subnet.subnet_id
  tags       = local.tags
}

#---------------------------------------------------------------
# RDS Postgres Database for Apache Airflow Metadata
#---------------------------------------------------------------
module "db" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 5.0"

  identifier = local.airflow_name

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "14"
  family               = "postgres14" # DB parameter group
  major_engine_version = "14"         # DB option group
  instance_class       = "db.r5.large"  #outpost db https://docs.aws.amazon.com/fr_fr/AmazonRDS/latest/UserGuide/rds-on-outposts.db-instance-classes.html

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name                = local.airflow_name
  username               = local.airflow_name
  create_random_password = false
  password               = sensitive(aws_secretsmanager_secret_version.postgres[0].secret_string)
  port                   = 5432

  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.private.name
  vpc_security_group_ids = [module.security_group[0].security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  # RDS on Outposts doesn't support Enhanced Monitoring
  performance_insights_enabled          = false
  create_monitoring_role                = false
  monitoring_interval                   = 0
  monitoring_role_name                  = null
  monitoring_role_use_name_prefix       = false
  monitoring_role_description           = null

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
# Apache Airflow Postgres Metastore DB Master password
#---------------------------------------------------------------
resource "random_password" "postgres" {
  count   = var.enable_airflow ? 1 : 0
  length  = 16
  special = false
}
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "postgres" {
  count                   = var.enable_airflow ? 1 : 0
  name                    = "postgres-2"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "postgres" {
  count         = var.enable_airflow ? 1 : 0
  secret_id     = aws_secretsmanager_secret.postgres[0].id
  secret_string = random_password.postgres[0].result
}

#---------------------------------------------------------------
# PostgreSQL RDS security group
#---------------------------------------------------------------
module "security_group" {
  count   = var.enable_airflow ? 1 : 0
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
      cidr_blocks = local.private_subnets_cidr[0]
    },
  ]

  tags = local.tags
}

#---------------------------------------------------------------
# Airflow Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace_v1" "airflow" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name = local.airflow_namespace
  }
  timeouts {
    delete = "15m"
  }
}

#---------------------------------------------------------------
# IRSA module for Airflow Scheduler
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_scheduler" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name        = local.airflow_scheduler_service_account
    namespace   = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_scheduler[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_scheduler" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_scheduler[0].metadata[0].name}-secret"
    namespace = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_scheduler[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_scheduler" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" # ensure to update this to the latest/desired version

  count = var.enable_airflow ? 1 : 0
  # IAM role for service account (IRSA)
  create_release = false
  create_policy  = false # Policy is created in the next resource

  create_role = var.enable_airflow
  role_name   = local.airflow_scheduler_service_account

  role_policies = { AirflowScheduler = aws_iam_policy.airflow_scheduler[0].arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = kubernetes_namespace_v1.airflow[0].metadata[0].name
      service_account = local.airflow_scheduler_service_account
    }
  }
}

resource "aws_iam_policy" "airflow_scheduler" {
  count = var.enable_airflow ? 1 : 0

  description = "IAM policy for Airflow Scheduler Pod"
  name_prefix = local.airflow_scheduler_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3[0].json
}

#---------------------------------------------------------------
# IRSA module for Airflow Webserver
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name        = local.airflow_webserver_service_account
    namespace   = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_webserver[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_webserver[0].metadata[0].name}-secret"
    namespace = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_webserver[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_webserver" {
  count = var.enable_airflow ? 1 : 0

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = var.enable_airflow
  create_policy = false # Policy is created in the next resource

  role_name     = local.airflow_webserver_service_account
  role_policies = merge({ AirflowWebserver = aws_iam_policy.airflow_webserver[0].arn })

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = kubernetes_namespace_v1.airflow[0].metadata[0].name
      service_account = local.airflow_webserver_service_account
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0

  description = "IAM policy for Airflow Webserver Pod"
  name_prefix = local.airflow_webserver_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3[0].json
}

#---------------------------------------------------------------
# Apache Airflow Webserver Secret
#---------------------------------------------------------------
resource "random_id" "airflow_webserver" {
  count       = var.enable_airflow ? 1 : 0
  byte_length = 16
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "airflow_webserver" {
  count                   = var.enable_airflow ? 1 : 0
  name                    = "airflow_webserver_secret_key_2"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "airflow_webserver" {
  count         = var.enable_airflow ? 1 : 0
  secret_id     = aws_secretsmanager_secret.airflow_webserver[0].id
  secret_string = random_id.airflow_webserver[0].hex
}

#---------------------------------------------------------------
# Webserver Secret Key
#---------------------------------------------------------------
resource "kubectl_manifest" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0
  sensitive_fields = [
    "data.webserver-secret-key"
  ]

  yaml_body = <<-YAML
apiVersion: v1
kind: Secret
metadata:
   name: ${local.airflow_webserver_secret_name}
   namespace: ${kubernetes_namespace_v1.airflow[0].metadata[0].name}
   labels:
    app.kubernetes.io/managed-by: "Helm"
   annotations:
    meta.helm.sh/release-name: "airflow"
    meta.helm.sh/release-namespace: "airflow"
type: Opaque
data:
  webserver-secret-key: ${base64encode(aws_secretsmanager_secret_version.airflow_webserver[0].secret_string)}
YAML
}

#---------------------------------------------------------------
# IRSA module for Airflow Workers
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_worker" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name        = local.airflow_workers_service_account
    namespace   = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_worker[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_worker" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name      = "${local.airflow_workers_service_account}-secret"
    namespace = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_worker[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

# Create IAM Role for Service Account (IRSA) Only if Airflow is enabled
module "airflow_irsa_worker" {
  count = var.enable_airflow ? 1 : 0

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  create_policy = false # Policy is created in the next resource

  role_name     = local.airflow_workers_service_account
  role_policies = merge({ AirflowWorker = aws_iam_policy.airflow_worker[0].arn })

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = kubernetes_namespace_v1.airflow[0].metadata[0].name
      service_account = local.airflow_workers_service_account
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "airflow_worker" {
  count = var.enable_airflow ? 1 : 0

  description = "IAM policy for Airflow Workers Pod"
  name_prefix = local.airflow_workers_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3[0].json
}

#---------------------------------------------------------------
# S3 log bucket for Airflow Logs
#---------------------------------------------------------------

#tfsec:ignore:*
module "airflow_s3_bucket" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-airflow-"

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
# Example IAM policy for Aiflow S3 logging
#---------------------------------------------------------------
data "aws_iam_policy_document" "airflow_s3" {
  count = var.enable_airflow ? 1 : 0
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}"]

    actions = [
      "s3:ListBucket"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}/*"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }
}
