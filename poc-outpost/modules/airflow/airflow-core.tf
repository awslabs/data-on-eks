#---------------------------------------------------------------
# RDS Postgres Database for Apache Airflow Metadata
#---------------------------------------------------------------
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 5.0"

  identifier = local.airflow_name

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "17"
  family               = "postgres17" # DB parameter group
  major_engine_version = "17"         # DB option group
  #instance_class       = "db.r5.large"  #outpost db https://docs.aws.amazon.com/fr_fr/AmazonRDS/latest/UserGuide/rds-on-outposts.db-instance-classes.html
  instance_class       = "db.r5.xlarge"  #outpost db https://docs.aws.amazon.com/fr_fr/AmazonRDS/latest/UserGuide/rds-on-outposts.db-instance-classes.html

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name                = local.airflow_name
  username               = local.airflow_name
  create_random_password = false
  password               = sensitive(aws_secretsmanager_secret_version.postgres.secret_string)
  port                   = 5432

  multi_az               = false
  db_subnet_group_name   = local.db_subnet_group_name
  vpc_security_group_ids = [module.security_group.security_group_id]

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
  length  = 16
  special = false
}
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "postgres" {
  name                    = "postgres-2-${local.name}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id     = aws_secretsmanager_secret.postgres.id
  secret_string = random_password.postgres.result
}

#---------------------------------------------------------------
# PostgreSQL RDS security group
#---------------------------------------------------------------
module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.name
  description = "Complete PostgreSQL security group"
  vpc_id      = local.vpc_id

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
# S3 bucket for Airflow
#---------------------------------------------------------------

#tfsec:ignore:*
module "airflow_s3_bucket" {
  source  = "../s3-bucket-outpost"

  bucket_name = "${local.name}-airflow"
  vpc-id      = local.vpc_id
  outpost_name = local.outpost_name
  output_subnet_id = local.output_subnet_id
  vpc_id = local.vpc_id

  tags = local.tags
}

#---------------------------------------------------------------
# Airflow Namespace
#---------------------------------------------------------------
resource "kubectl_manifest" "airflow" {
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${local.airflow_namespace}
YAML
  }

#---------------------------------------------------------------
# IRSA module for Airflow Scheduler
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_scheduler" {
  metadata {
    name        = local.airflow_scheduler_service_account
    namespace   = local.airflow_namespace
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_scheduler.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_scheduler" {
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_scheduler.metadata[0].name}-secret"
    namespace = local.airflow_namespace
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_scheduler.metadata[0].name
      "kubernetes.io/service-account.namespace" = local.airflow_namespace
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_scheduler" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" # ensure to update this to the latest/desired version

  # IAM role for service account (IRSA)
  create_release = false
  create_policy  = false # Policy is created in the next resource

  create_role = true
  role_name   = local.airflow_scheduler_service_account

  role_policies = { AirflowScheduler = aws_iam_policy.airflow_scheduler.arn }

  oidc_providers = {
    this = {
      provider_arn    = local.oidc_provider_arn
      namespace       = local.airflow_namespace
      service_account = local.airflow_scheduler_service_account
    }
  }
}

resource "aws_iam_policy" "airflow_scheduler" {

  description = "IAM policy for Airflow Scheduler Pod"
  name_prefix = local.airflow_scheduler_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_outpost.json
}

#---------------------------------------------------------------
# IRSA module for Airflow Webserver
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_webserver" {
  metadata {
    name        = local.airflow_api_server_service_account
    namespace   = local.airflow_namespace
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_webserver.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_webserver" {
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_webserver.metadata[0].name}-secret"
    namespace = local.airflow_namespace
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_webserver.metadata[0].name
      "kubernetes.io/service-account.namespace" = local.airflow_namespace
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_webserver" {

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  create_policy = false # Policy is created in the next resource

  role_name     = local.airflow_api_server_service_account
  role_policies = merge({ AirflowWebserver = aws_iam_policy.airflow_webserver.arn })

  oidc_providers = {
    this = {
      provider_arn    = local.oidc_provider_arn
      namespace       = local.airflow_namespace
      service_account = local.airflow_api_server_service_account
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "airflow_webserver" {

  description = "IAM policy for Airflow Webserver Pod"
  name_prefix = local.airflow_api_server_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_outpost.json
}

#---------------------------------------------------------------
# Apache Airflow Webserver Secret
#---------------------------------------------------------------
resource "random_id" "airflow_webserver" {
  byte_length = 16
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "airflow_webserver" {
  name                    = "airflow_webserver_secret_key_2${local.name}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "airflow_webserver" {
  secret_id     = aws_secretsmanager_secret.airflow_webserver.id
  secret_string = random_id.airflow_webserver.hex
}

#---------------------------------------------------------------
# Webserver Secret Key
#---------------------------------------------------------------
resource "kubectl_manifest" "airflow_webserver" {
  sensitive_fields = [
    "data.webserver-secret-key"
  ]

  yaml_body = <<-YAML
apiVersion: v1
kind: Secret
metadata:
   name: ${local.airflow_webserver_secret_name}
   namespace: ${local.airflow_namespace}
   labels:
    app.kubernetes.io/managed-by: "Helm"
   annotations:
    meta.helm.sh/release-name: "airflow"
    meta.helm.sh/release-namespace: "airflow"
type: Opaque
data:
  webserver-secret-key: ${base64encode(aws_secretsmanager_secret_version.airflow_webserver.secret_string)}
YAML
}

#---------------------------------------------------------------
# IRSA module for Airflow Workers
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_worker" {
  metadata {
    name        = local.airflow_workers_service_account
    namespace   = local.airflow_namespace
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_worker.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_worker" {
  metadata {
    name      = "${local.airflow_workers_service_account}-secret"
    namespace = local.airflow_namespace
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_worker.metadata[0].name
      "kubernetes.io/service-account.namespace" = local.airflow_namespace
    }
  }

  type = "kubernetes.io/service-account-token"
}

# Create IAM Role for Service Account (IRSA) Only if Airflow is enabled
module "airflow_irsa_worker" {

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  create_policy = false # Policy is created in the next resource

  role_name     = local.airflow_workers_service_account
  role_policies = merge({ AirflowWorker = aws_iam_policy.airflow_worker.arn })

  oidc_providers = {
    this = {
      provider_arn    = local.oidc_provider_arn
      namespace       = local.airflow_namespace
      service_account = local.airflow_workers_service_account
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "airflow_worker" {

  description = "IAM policy for Airflow Workers Pod"
  name_prefix = local.airflow_workers_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_outpost.json
}

#---------------------------------------------------------------
# IRSA module for Airflow Dag processor
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_dag" {
  metadata {
    name        = local.airflow_dag_processor_service_account
    namespace   = local.airflow_namespace
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_dag.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_dag" {
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_dag.metadata[0].name}-secret"
    namespace = local.airflow_namespace
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_dag.metadata[0].name
      "kubernetes.io/service-account.namespace" = local.airflow_namespace
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_dag" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" # ensure to update this to the latest/desired version

  # IAM role for service account (IRSA)
  create_release = false
  create_policy  = false # Policy is created in the next resource

  create_role = true
  role_name   = local.airflow_dag_processor_service_account


  role_policies = { AirflowDag = aws_iam_policy.airflow_dag.arn }

  oidc_providers = {
    this = {
      provider_arn    = local.oidc_provider_arn
      namespace       = local.airflow_namespace
      service_account = local.airflow_dag_processor_service_account
    }
  }
}

resource "aws_iam_policy" "airflow_dag" {

  description = "IAM policy for Airflow Scheduler Pod"
  name_prefix = local.airflow_dag_processor_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_outpost.json
}

#---------------------------------------------------------------
# IAM policy for Aiflow S3
#---------------------------------------------------------------
data "aws_iam_policy_document" "airflow_s3_outpost" {
  statement {
    sid =  "AccessPointAccess"
    effect    = "Allow"
    resources = [
      "${module.airflow_s3_bucket.s3_access_arn}",
      "${module.airflow_s3_bucket.s3_access_arn}/*"
    ]

    actions = [
      "s3-outposts:GetObject",
      "s3-outposts:PutObject",
      "s3-outposts:DeleteObject",
      "s3-outposts:ListBucket"
    ]
  }
  statement {
    sid =  "BucketAccess"
    effect    = "Allow"
    resources = [
      "${module.airflow_s3_bucket.s3_bucket_arn}",
      "${module.airflow_s3_bucket.s3_bucket_arn}/*"]

    actions = [
      "s3-outposts:GetObject",
      "s3-outposts:PutObject",
      "s3-outposts:DeleteObject",
      "s3-outposts:ListBucket"
    ]
  }
}
