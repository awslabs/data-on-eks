#---------------------------------------------------------------
# RDS Postgres Database for Apache Airflow Metadata
#---------------------------------------------------------------
module "db" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 5.0"

  identifier = local.airflow_name

  engine               = "postgres"
  engine_version       = "14.3"
  family               = "postgres14"
  major_engine_version = "14"
  instance_class       = "db.m6i.xlarge"

  storage_type      = "io1"
  allocated_storage = 100
  iops              = 3000

  db_name                = local.airflow_name
  username               = local.airflow_name
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
  monitoring_role_name                  = "airflow-metastore"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "Airflow Postgres Metastore for monitoring role"

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
      cidr_blocks = "${module.vpc.vpc_cidr_block},${module.vpc.vpc_secondary_cidr_blocks[0]}"
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
  policy      = data.aws_iam_policy_document.airflow_s3_logs[0].json
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
  policy      = data.aws_iam_policy_document.airflow_s3_logs[0].json
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
  policy      = data.aws_iam_policy_document.airflow_s3_logs[0].json
}

#---------------------------------------------------------------
# Managing DAG files with GitSync - EFS Storage Class
#---------------------------------------------------------------
resource "kubectl_manifest" "efs_sc" {
  count     = var.enable_airflow ? 1 : 0
  yaml_body = <<-YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${local.efs_storage_class}
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${aws_efs_file_system.efs[0].id}
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
YAML

  depends_on = [module.eks.cluster_name]
}

#---------------------------------------------------------------
# Persistent Volume Claim for EFS
#---------------------------------------------------------------
resource "kubectl_manifest" "efs_pvc" {
  count     = var.enable_airflow ? 1 : 0
  yaml_body = <<-YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${local.efs_pvc}
  namespace: ${kubernetes_namespace_v1.airflow[0].metadata[0].name}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${local.efs_storage_class}
  resources:
    requests:
      storage: 10Gi
YAML

  depends_on = [kubectl_manifest.efs_sc]
}
#---------------------------------------------------------------
# EFS Filesystem for Airflow DAGs
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  count          = var.enable_airflow ? 1 : 0
  creation_token = "efs"
  encrypted      = true

  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  count = var.enable_airflow ? length(var.eks_data_plane_subnet_secondary_cidr) : 0

  file_system_id  = aws_efs_file_system.efs[0].id
  subnet_id       = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_security_group" "efs" {
  count       = var.enable_airflow ? 1 : 0
  name        = "${local.name}-efs"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}

#---------------------------------------------------------------
# S3 log bucket for Airflow Logs
#---------------------------------------------------------------

#tfsec:ignore:*
module "airflow_s3_bucket" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-logs-"

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
data "aws_iam_policy_document" "airflow_s3_logs" {
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
