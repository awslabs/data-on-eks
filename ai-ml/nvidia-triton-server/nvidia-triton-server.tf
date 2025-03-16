locals {
  triton_model = "triton-vllm"
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "triton_server_vllm" {
  count      = var.enable_nvidia_triton_server ? 1 : 0
  depends_on = [module.eks_blueprints_addons.kube_prometheus_stack]
  source     = "aws-ia/eks-data-addons/aws"
  version    = "~> 1.32.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_nvidia_triton_server = true

  nvidia_triton_server_helm_config = {
    version   = "1.0.0"
    timeout   = 120
    wait      = false
    namespace = kubernetes_namespace_v1.triton[count.index].metadata[0].name
    values = [
      <<-EOT
      replicaCount: 1
      image:
        repository: nvcr.io/nvidia/tritonserver
        tag: "24.06-vllm-python-py3"
      serviceAccount:
        create: false
        name: ${kubernetes_service_account_v1.triton[count.index].metadata[0].name}
      modelRepositoryPath: s3://${module.s3_bucket[count.index].s3_bucket_id}/model_repository
      environment:
        - name: "LD_PRELOAD"
          value: ""
        - name: "TRANSFORMERS_CACHE"
          value: "/home/triton-server/.cache"
        - name: "shm-size"
          value: "5g"
        - name: "NCCL_IGNORE_DISABLED_P2P"
          value: "1"
        - name: tensor_parallel_size
          value: "1"
        - name: gpu_memory_utilization
          value: "0.8"
        - name: dtype
          value: "auto"
      secretEnvironment:
        - name: "HUGGING_FACE_TOKEN"
          secretName: ${kubernetes_secret_v1.huggingface_token[count.index].metadata[0].name}
          key: "HF_TOKEN"
      resources:
        limits:
          cpu: 10
          memory: 60Gi
          nvidia.com/gpu: 4
        requests:
          cpu: 10
          memory: 60Gi
          nvidia.com/gpu: 4
      nodeSelector:
        NodeGroupType: g5-gpu-karpenter
        type: karpenter
      hpa:
        minReplicas: 1
        maxReplicas: 5
        metrics:
          - type: Pods
            pods:
              metric:
                name: queue_compute_ratio
              target:
                type: AverageValue
                averageValue: 1000m
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
      EOT
    ]
  }
}

#---------------------------------------------------------------
# Hugging Face Token
# Replace the value with your Hugging Face token
#---------------------------------------------------------------
resource "kubernetes_secret_v1" "huggingface_token" {
  count = var.enable_nvidia_triton_server ? 1 : 0
  metadata {
    name      = "huggingface-secret"
    namespace = kubernetes_namespace_v1.triton[count.index].metadata[0].name
  }

  data = {
    HF_TOKEN = var.huggingface_token
  }
}

#---------------------------------------------------------------
# S3 bucket for vLLM model configuration
#---------------------------------------------------------------
#tfsec:ignore:*
module "s3_bucket" {
  count   = var.enable_nvidia_triton_server ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.1.2"

  bucket_prefix = "${local.name}-${local.triton_model}-"

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

# Use null_resource to sync local files to the S3 bucket
resource "null_resource" "sync_local_to_s3" {
  count = var.enable_nvidia_triton_server ? 1 : 0
  # Re-run the provisioner if the bucket name changes
  triggers = {
    always_run  = uuid(),
    bucket_name = module.s3_bucket[count.index].s3_bucket_id
  }

  provisioner "local-exec" {
    command = "aws s3 sync ../../gen-ai/inference/vllm-nvidia-triton-server-gpu/ s3://${module.s3_bucket[count.index].s3_bucket_id}"
  }
}

#---------------------------------------------------------------
# IAM role for service account (IRSA)
#---------------------------------------------------------------
resource "kubernetes_namespace_v1" "triton" {
  count = var.enable_nvidia_triton_server ? 1 : 0
  metadata {
    name = local.triton_model
  }
  timeouts {
    delete = "15m"
  }
}

#---------------------------------------------------------------
# Service account for Triton model
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "triton" {
  count = var.enable_nvidia_triton_server ? 1 : 0
  metadata {
    name        = local.triton_model
    namespace   = kubernetes_namespace_v1.triton[count.index].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.triton_irsa[count.index].iam_role_arn }
  }

  automount_service_account_token = true
}

#---------------------------------------------------------------
# Secret for Triton model
#---------------------------------------------------------------
resource "kubernetes_secret_v1" "triton" {
  count = var.enable_nvidia_triton_server ? 1 : 0
  metadata {
    name      = "${local.triton_model}-secret"
    namespace = kubernetes_namespace_v1.triton[count.index].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.triton[count.index].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.triton[count.index].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# IRSA for Triton model server pods
#---------------------------------------------------------------
module "triton_irsa" {
  count   = var.enable_nvidia_triton_server ? 1 : 0
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0"

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${var.name}-${local.triton_model}"
  create_policy = false
  role_policies = {
    triton_policy = aws_iam_policy.triton[count.index].arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.triton_model
      service_account = local.triton_model
    }
  }
}

#---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for Triton model server pods
#---------------------------------------------------------------
resource "aws_iam_policy" "triton" {
  count       = var.enable_nvidia_triton_server ? 1 : 0
  description = "IAM role policy for Triton models"
  name        = "${local.name}-${local.triton_model}-irsa"
  policy      = data.aws_iam_policy_document.triton_model.json
}

#---------------------------------------------------------------
# Example IAM policy for Triton model server pods
#---------------------------------------------------------------
data "aws_region" "current" {}


data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "triton_model" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}
