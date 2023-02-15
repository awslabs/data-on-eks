#------------------------------------------------------------------------
# AWS MWAA Module
#------------------------------------------------------------------------

module "mwaa" {
  source  = "aws-ia/mwaa/aws"
  version = "0.0.1"

  name                  = local.name
  airflow_version       = "2.2.2"
  environment_class     = "mw1.medium"  # mw1.small / mw1.medium / mw1.large
  webserver_access_mode = "PUBLIC_ONLY" # Default PRIVATE_ONLY for production environments

  create_s3_bucket  = false
  source_bucket_arn = module.s3_bucket.s3_bucket_arn

  dag_s3_path          = local.dag_s3_path
  requirements_s3_path = "${local.dag_s3_path}/requirements.txt"

  min_workers = 1
  max_workers = 25

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = slice(module.vpc.private_subnets, 0, 2) # Required 2 subnets only
  source_cidr        = [module.vpc.vpc_cidr_block]             # Add your IP here to access Airflow UI

  airflow_configuration_options = {
    "core.load_default_connections" = "false"
    "core.load_examples"            = "false"
    "webserver.dag_default_view"    = "tree"
    "webserver.dag_orientation"     = "TB"
    "logging.logging_level"         = "INFO"
  }

  logging_configuration = {
    dag_processing_logs = {
      enabled   = true
      log_level = "INFO"
    }

    scheduler_logs = {
      enabled   = true
      log_level = "INFO"
    }

    task_logs = {
      enabled   = true
      log_level = "INFO"
    }

    webserver_logs = {
      enabled   = true
      log_level = "INFO"
    }

    worker_logs = {
      enabled   = true
      log_level = "INFO"
    }
  }

  tags = local.tags
}

#------------------------------------------------------------------------
# Additional IAM policies for MWAA execution role to run emr on eks job
#------------------------------------------------------------------------
resource "aws_iam_policy" "this" {
  name        = format("%s-%s", local.name, "mwaa-emr-job")
  description = "IAM policy for MWAA RUN EMR on EKS Job execution"
  path        = "/"
  policy      = data.aws_iam_policy_document.mwaa_emrjob.json
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = module.mwaa.mwaa_role_name
  policy_arn = aws_iam_policy.this.arn
}

#------------------------------------------------------------------------
# Dags and Requirements
#------------------------------------------------------------------------

#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "mwaa-${random_id.this.hex}"
  acl    = "private"

  # For example only - please evaluate for your environment
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

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

# Kubeconfig is required for KubernetesPodOperator
# https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/operators.html
locals {
  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "mwaa"
    clusters = [{
      name = module.eks_blueprints.eks_cluster_arn
      cluster = {
        certificate-authority-data = module.eks_blueprints.eks_cluster_certificate_authority_data
        server                     = module.eks_blueprints.eks_cluster_endpoint
      }
    }]
    contexts = [{
      name = "mwaa" # must match KubernetesPodOperator context
      context = {
        cluster = module.eks_blueprints.eks_cluster_arn
        user    = "mwaa"
      }
    }]
    users = [{
      name = "mwaa"
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args = [
            "--region",
            local.region,
            "eks",
            "get-token",
            "--cluster-name",
            local.name
          ]
        }
      }
    }]
  })
}

resource "aws_s3_bucket_object" "kube_config" {
  bucket  = module.s3_bucket.s3_bucket_id
  key     = "${local.dag_s3_path}/kube_config.yaml"
  content = local.kubeconfig
  etag    = md5(local.kubeconfig)
}

resource "aws_s3_bucket_object" "uploads" {
  for_each = fileset("${local.dag_s3_path}/", "*")

  bucket = module.s3_bucket.s3_bucket_id
  key    = "${local.dag_s3_path}/${each.value}"
  source = "${local.dag_s3_path}/${each.value}"
  etag   = filemd5("${local.dag_s3_path}/${each.value}")
}

resource "random_id" "this" {
  byte_length = "2"
}
