#---------------------------------------------------------------
# spark history server Namespace
#---------------------------------------------------------------

# resource "kubernetes_namespace" "spark_history_server_namespace" {
#   metadata {
#     name = "${local.spark_history_server_namespace}"
#   }
# }

#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
# module "eks_blueprints_addons" {
#   source  = "aws-ia/eks-blueprints-addons/aws"
#   version = "~> 1.20"
#
#   cluster_name      = local.name
#   cluster_endpoint  = local.cluster_endpoint
#   cluster_version   = local.cluster_version
#   oidc_provider_arn = local.oidc_provider_arn
#
#   #---------------------------------------
#   # AWS for FluentBit - DaemonSet
#   #---------------------------------------
#   enable_aws_for_fluentbit = true
#   aws_for_fluentbit_cw_log_group = {
#     use_name_prefix   = false
#     name = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
#     retention_in_days = 30
#   }
#   aws_for_fluentbit = {
#     chart_version = "0.1.34"
#     s3_bucket_arns = [
#       module.s3_bucket.s3_bucket_arn,
#       "${module.s3_bucket.s3_bucket_arn}/*"
#     ]
#     values = [
#       templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
#         region               = local.region,
#         cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
#         s3_bucket_name       = module.s3_bucket.s3_bucket_id
#         cluster_name         = local.name
#       })
#     ]
#   }
#
# }

  #---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source = "aws-ia/eks-data-addons/aws"
  version = "1.37.1" # ensure to update this to the latest/desired version

  oidc_provider_arn = local.oidc_provider_arn

  #---------------------------------------------------------------
  # Spark Operator Add-on
  #---------------------------------------------------------------
  enable_spark_operator = true
  spark_operator_helm_config = {
    version = "2.2.0"
    timeout = "120"
    values = [
      <<-EOT
        controller:
          # -- Number of replicas of controller.
          replicas: 1
          # -- Reconcile concurrency, higher values might increase memory usage.
          # -- Increased from 10 to 20 to leverage more cores from the instance
          workers: 20
          # -- Change this to True when YuniKorn is deployed
          batchScheduler:
            enable: true
            default: "yunikorn"
        spark:
          # -- List of namespaces where to run spark jobs.
          # If empty string is included, all namespaces will be allowed.
          # Make sure the namespaces have already existed.
          jobNamespaces:
            - ""
          serviceAccount:
            # -- Specifies whether to create a service account for the controller.
            create: true
          rbac:
            # -- Specifies whether to create RBAC resources for the controller.
            create: true
        prometheus:
          metrics:
            enable: true
            port: 8080
            portName: metrics
            endpoint: /metrics
            prefix: ""
          # Prometheus pod monitor for controller pods
          # Note: The kube-prometheus-stack addon must deploy before the PodMonitor CRD is available.
          #       This can cause the terraform apply to fail since the addons are deployed in parallel
          podMonitor:
            # -- Specifies whether to create pod monitor.
            create: true
            labels: {}
            # -- The label to use to retrieve the job name from
            jobLabel: spark-operator-podmonitor
            # -- Prometheus metrics endpoint properties. `metrics.portName` will be used as a port
            podMetricsEndpoint:
              scheme: http
              interval: 5s
      EOT
    ]
  }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  yunikorn_helm_config = {
    version = "1.6.3"
    values  = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # Spark History Server Add-on
  #---------------------------------------------------------------
  # Spark history server is required only when EMR Spark Operator is enabled
  enable_spark_history_server = true

  spark_history_server_helm_config = {
    role_policy_arns = {
      S3OutpostFullPolicy = "arn:aws:iam::aws:policy/AmazonS3OutpostsFullAccess"
    }
    version = "1.3.2"
    values = [
      <<-EOT
      sparkHistoryOpts: "-Dspark.history.fs.logDirectory=s3a://${module.s3_bucket.s3_bucket_id}/spark-event-logs/"

      sparkConf: |-
        spark.hadoop.fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider
        spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem
        #spark.hadoop.fs.s3a.connection.ssl.enabled=true
        spark.hadoop.fs.s3a.path.style.access=true
        spark.hadoop.fs.s3a.endpoint=s3-outposts.${local.region}.amazonaws.com
        #spark.hadoop.fs.s3a.signing-algorithm=SignatureV4
        spark.hadoop.fs.s3a.connection.timeout=10000

        spark.eventLog.enabled=true
        #spark.eventLog.dir=s3a://${module.s3_bucket.s3_bucket_id}/spark-event-logs
        #spark.history.fs.logDirectory=s3a://${module.s3_bucket.s3_bucket_id}/spark-event-logs
        spark.history.fs.eventLog.rolling.maxFilesToRetain=5
        spark.history.ui.port=18080
      EOT
    ]
  }

  # #---------------------------------------------------------------
  # # Kubecost Add-on
  # #---------------------------------------------------------------
  # enable_kubecost = true
  # kubecost_helm_config = {
  #   version             = "2.7.0"
  #   values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
  #   repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  #   repository_password = data.aws_ecrpublic_authorization_token.token.password
  # }

  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  # enable_jupyterhub = true
  # jupyterhub_helm_config = {
  #   values = [templatefile("${path.module}/helm-values/jupyterhub-singleuser-values.yaml", {
  #     jupyter_single_user_sa_name = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
  #   })]
  #   version = "3.3.8"
  # }

  # depends_on = [kubernetes_service_account_v1.spark_history_server]
}

#---------------------------------------------------------------
# S3 bucket for Spark Event Logs and Example Data
#---------------------------------------------------------------
#tfsec:ignore:*
module "s3_bucket" {
  source  = "../s3-bucket-outpost"

  bucket_name = "${local.name}-spark-logs"
  vpc-id      = local.vpc_id
  outpost_name = local.outpost_name
  output_subnet_id = local.output_subnet_id
  vpc_id = local.vpc_id

  tags = local.tags
}


#---------------------------------------------------------------
# IAM Policy for FluentBit Add-on
#---------------------------------------------------------------
# resource "aws_iam_policy" "fluentbit" {
#   description = "IAM policy policy for FluentBit"
#   name        = "${local.name}-fluentbit-additional"
#   policy      = data.aws_iam_policy_document.fluent_bit.json
# }

#---------------------------------------------------------------
# IAM policy for FluentBit
#---------------------------------------------------------------
# data "aws_iam_policy_document" "fluent_bit" {
#   statement {
#     sid       = ""
#     effect    = "Allow"
#     resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.s3_bucket.s3_bucket_id}/*"]
#
#     actions = [
#       "s3:ListBucket",
#       "s3:PutObject",
#       "s3:PutObjectAcl",
#       "s3:GetObject",
#       "s3:GetObjectAcl",
#       "s3:DeleteObject",
#       "s3:DeleteObjectVersion"
#     ]
#   }
# }


#---------------------------------------------------------------
# IRSA module spark history server
#---------------------------------------------------------------
# resource "kubernetes_namespace_v1" "spark_history_server_namespace" {
#
#   metadata {
#     name = local.spark_history_server_namespace
#   }
#
#   lifecycle {
#     ignore_changes = [metadata]
#     prevent_destroy = true
#   }
# }
#
# resource "kubernetes_service_account_v1" "spark_history_server" {
#   metadata {
#     name        = local.spark_history_server_service_account
#     namespace   = local.spark_history_server_namespace
#     annotations = { "eks.amazonaws.com/role-arn" : module.spark_history_server_irsa.iam_role_arn }
#   }
#
#   automount_service_account_token = true
# }
#
# resource "kubernetes_secret_v1" "spark_history_server" {
#   metadata {
#     name      = "${kubernetes_service_account_v1.spark_history_server.metadata[0].name}-secret"
#     namespace = local.spark_history_server_namespace
#     annotations = {
#       "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.spark_history_server.metadata[0].name
#       "kubernetes.io/service-account.namespace" = local.spark_history_server_namespace
#     }
#   }
#
#   type = "kubernetes.io/service-account-token"
# }
#
# module "spark_history_server_irsa" {
#   source  = "aws-ia/eks-blueprints-addon/aws"
#   version = "~> 1.0" # ensure to update this to the latest/desired version
#
#   # IAM role for service account (IRSA)
#   create_release = false
#   create_policy  = false # Policy is created in the next resource
#
#   create_role = true
#   role_name   = local.spark_history_server_service_account
#
#   role_policies = { SparkHistoryServer = aws_iam_policy.spark_history_server.arn }
#
#   oidc_providers = {
#     this = {
#       provider_arn    = local.oidc_provider_arn
#       namespace       = local.spark_history_server_namespace
#       service_account = local.spark_history_server_service_account
#     }
#   }
# }
#
# resource "aws_iam_policy" "spark_history_server" {
#
#   description = "IAM policy for spark history server Pod"
#   name_prefix = local.spark_history_server_service_account
#   path        = "/"
#   policy      = data.aws_iam_policy_document.s3_outpost.json
# }


# ---------------------------------------------------------------
# IAM policy for Aiflow S3
# ---------------------------------------------------------------
# data "aws_iam_policy_document" "s3_outpost" {
#   statement {
#     sid    = "AccessPointAccess"
#     effect = "Allow"
#     resources = [
#       "${module.s3_bucket.s3_access_arn}",
#       "${module.s3_bucket.s3_access_arn}/*"
#     ]
#     actions = [
#       "s3-outposts:Get*",
#       "s3-outposts:Describe*",
#       "s3-outposts:List*",
#       "s3-object-lambda:Get*",
#       "s3-object-lambda:List*"
#     ]
#   }
#   statement {
#     sid    = "BucketAccess"
#     effect = "Allow"
#     resources = [
#       "${module.s3_bucket.s3_bucket_arn}",
#       "${module.s3_bucket.s3_bucket_arn}/*"
#     ]
#
#     actions = [
#       "s3-outposts:Get*",
#       "s3-outposts:Describe*",
#       "s3-outposts:List*",
#       "s3-object-lambda:Get*",
#       "s3-object-lambda:List*"
#     ]
#   }
# }


#---------------------------------------------------------------
# S3Table IAM policy for Karpenter nodes
# The S3 tables library does not fully support IRSA and Pod Identity as of this writing.
# We give the node role access to S3tables to work around this limitation.
#---------------------------------------------------------------
resource "aws_iam_policy" "s3tables_policy" {
  name_prefix = "${local.name}-s3tables"
  path        = "/"
  description = "S3Tables Metadata access for Nodes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetNamespace",
          "s3tables:ListTableBuckets",
          "s3tables:ListNamespaces",
          "s3tables:GetTableBucket",
          "s3tables:GetTableBucketMaintenanceConfiguration",
          "s3tables:GetTableBucketPolicy",
          "s3tables:CreateNamespace",
          "s3tables:CreateTable"
        ]
        Resource = "arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*"
      },
      {
        Sid    = "VisualEditor1"
        Effect = "Allow"
        Action = [
          "s3tables:GetTableMaintenanceJobStatus",
          "s3tables:GetTablePolicy",
          "s3tables:GetTable",
          "s3tables:GetTableMetadataLocation",
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetTableData",
          "s3tables:GetTableMaintenanceConfiguration"
        ]
        Resource = "arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*/table/*"
      }
    ]
  })
}

# resource "kubernetes_pod" "init_s3_directory_spark_event_logs" {
#   metadata {
#     name      = "awscli-init-s3"
#     namespace = "${local.spark_history_server_namespace}"
#   }
#
#   spec {
#     service_account_name = "${local.spark_history_server_service_account}"
#
#     container {
#       name  = "awscli"
#       image = "amazon/aws-cli:latest"
#
#       command = [
#         "sh", "-c",
#         <<-EOT
#           aws s3 cp /etc/hostname s3://${module.s3_bucket.s3_bucket_id}/spark-event-logs/.init
#         EOT
#       ]
#     }
#
#     restart_policy = "Never"
#   }
#
#   depends_on = [module.eks_data_addons]
# }