#---------------------------------------------------------------
# agw-demo: agentgateway in front of Ray Serve + vLLM (ray-on-eks overlay)
#
# Base infrastructure for examples/agw-demo/. Everything is gated by
# enable_agw_demo; set it to false and re-run deploy.sh to remove it all.
#
#   - Karpenter: 2 EC2NodeClasses + 3 NodePools (cpu, gpu-gemma, gpu-embed)
#   - ElastiCache for Valkey (Multi-AZ, TLS + AUTH) for Ray GCS fault tolerance
#   - Pod Identity: read-only models/ access for Ray pods, scoped write
#     access for the one-time model staging Job
#   - Namespace agw-demo, its ServiceAccounts and the Valkey Secret
#
# RayServices, the Gateway and its policies are applied from examples/agw-demo.
#---------------------------------------------------------------

variable "enable_agw_demo" {
  description = "Create base infrastructure for the agentgateway + Ray Serve demo (examples/agw-demo)"
  type        = bool
  default     = false
}

locals {
  # Demo GPU workers (one per AZ) and the Valkey primary/replica use the first
  # two AZs of the cluster's region (vpc.tf local.azs; e.g. us-west-2a/2b).
  # Fixed for the demo: not a user setting.
  agw_demo_gpu_zones = slice(local.azs, 0, 2)

  agw_demo_namespace        = "agw-demo"
  agw_demo_ray_sa           = "agw-ray"
  agw_demo_stager_sa        = "agw-model-stager"
  agw_demo_models_prefix    = "models"
  agw_demo_embed_model_dir  = "qwen3-embedding-0.6b"
  agw_demo_valkey_secret    = "agw-demo-valkey"
  agw_demo_valkey_node_type = "cache.t4g.small"

  agw_demo_tags = merge(local.tags, {
    project = "agw-demo"
    owner   = "vara"
  })

  agw_demo_karpenter_dir = "${path.module}/manifests/agw-demo/karpenter"
  agw_demo_karpenter_manifests = {
    for f in fileset(local.agw_demo_karpenter_dir, "*.yaml") :
    f => templatefile("${local.agw_demo_karpenter_dir}/${f}", {
      CLUSTER_NAME                 = local.name
      KARPENTER_NODE_IAM_ROLE_NAME = module.karpenter.node_iam_role_name
      GPU_ZONES                    = jsonencode(local.agw_demo_gpu_zones)
      ALL_ZONES                    = jsonencode(local.azs)
    }) if var.enable_agw_demo
  }

  # Non-secondary (10.0.x) private subnets, one per AZ, for ElastiCache.
  agw_demo_cache_subnet_ids = compact([
    for subnet_id, cidr in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
    substr(cidr, 0, 4) == "100." ? null : subnet_id
  ])
}

#---------------------------------------------------------------
# Karpenter: NodeClasses first, then NodePools that reference them
#---------------------------------------------------------------
resource "kubectl_manifest" "agw_demo_ec2nodeclass" {
  for_each = { for k, v in local.agw_demo_karpenter_manifests : k => v if startswith(k, "ec2nodeclass") }

  yaml_body = each.value
  wait      = true

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "agw_demo_nodepool" {
  for_each = { for k, v in local.agw_demo_karpenter_manifests : k => v if startswith(k, "nodepool") }

  yaml_body = each.value
  wait      = true

  depends_on = [kubectl_manifest.agw_demo_ec2nodeclass]
}

#---------------------------------------------------------------
# ElastiCache for Valkey — Ray GCS fault tolerance only
#---------------------------------------------------------------
resource "aws_elasticache_subnet_group" "agw_demo_valkey" {
  count = var.enable_agw_demo ? 1 : 0

  name        = "agw-demo-valkey"
  description = "agw-demo Valkey (Ray GCS FT) in ${local.name} private subnets"
  subnet_ids  = local.agw_demo_cache_subnet_ids

  tags = local.agw_demo_tags
}

resource "aws_security_group" "agw_demo_valkey" {
  count = var.enable_agw_demo ? 1 : 0

  name        = "agw-demo-valkey"
  description = "agw-demo Valkey: 6379 from EKS nodes only"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.agw_demo_tags, { Name = "agw-demo-valkey" })
}

# Pods use the node security group (no security groups for pods), and
# Karpenter nodes select the same group by its Name tag.
resource "aws_vpc_security_group_ingress_rule" "agw_demo_valkey_from_nodes" {
  count = var.enable_agw_demo ? 1 : 0

  security_group_id            = aws_security_group.agw_demo_valkey[0].id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Valkey from EKS nodes"

  tags = local.agw_demo_tags
}

# ElastiCache AUTH token: 16-128 printable chars, no @ " / — alphanumeric only.
resource "random_password" "agw_demo_valkey_auth" {
  count = var.enable_agw_demo ? 1 : 0

  length  = 40
  special = false
}

resource "aws_elasticache_replication_group" "agw_demo_valkey" {
  count = var.enable_agw_demo ? 1 : 0

  replication_group_id = "agw-demo-valkey"
  description          = "agw-demo: Ray GCS fault tolerance for gemma-12b and embeddings RayServices"

  engine               = "valkey"
  engine_version       = "8.2"
  parameter_group_name = "default.valkey8"
  node_type            = local.agw_demo_valkey_node_type
  port                 = 6379

  # Cluster mode disabled: 1 primary + 1 replica in the two GPU AZs.
  num_cache_clusters          = 2
  preferred_cache_cluster_azs = local.agw_demo_gpu_zones
  automatic_failover_enabled  = true
  multi_az_enabled            = true

  subnet_group_name  = aws_elasticache_subnet_group.agw_demo_valkey[0].name
  security_group_ids = [aws_security_group.agw_demo_valkey[0].id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.agw_demo_valkey_auth[0].result

  # Demo data is reconstructible Ray metadata: no snapshots.
  snapshot_retention_limit = 0
  apply_immediately        = true

  tags = local.agw_demo_tags
}

#---------------------------------------------------------------
# IAM (Pod Identity)
#---------------------------------------------------------------
resource "aws_iam_policy" "agw_demo_models_read" {
  count = var.enable_agw_demo ? 1 : 0

  name        = "agw-demo-models-read"
  description = "agw-demo Ray pods: read-only access to model weights under ${local.agw_demo_models_prefix}/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${module.s3_bucket.s3_bucket_arn}/${local.agw_demo_models_prefix}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [module.s3_bucket.s3_bucket_arn]
        Condition = {
          StringLike = { "s3:prefix" = ["${local.agw_demo_models_prefix}/*"] }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = [module.s3_bucket.s3_bucket_arn]
      }
    ]
  })

  tags = local.agw_demo_tags
}

resource "aws_iam_policy" "agw_demo_models_stage" {
  count = var.enable_agw_demo ? 1 : 0

  name        = "agw-demo-models-stage"
  description = "agw-demo model staging Job: write only ${local.agw_demo_models_prefix}/${local.agw_demo_embed_model_dir}/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/${local.agw_demo_models_prefix}/${local.agw_demo_embed_model_dir}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [module.s3_bucket.s3_bucket_arn]
        Condition = {
          StringLike = { "s3:prefix" = ["${local.agw_demo_models_prefix}/${local.agw_demo_embed_model_dir}*"] }
        }
      }
    ]
  })

  tags = local.agw_demo_tags
}

module "agw_demo_ray_pod_identity" {
  count   = var.enable_agw_demo ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name            = "agw-demo-ray"
  use_name_prefix = false

  additional_policy_arns = {
    models_read = aws_iam_policy.agw_demo_models_read[0].arn
  }

  associations = {
    agw_ray = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.agw_demo_namespace
      service_account = local.agw_demo_ray_sa
    }
  }

  tags = local.agw_demo_tags
}

# Write role used once by the staging Job. Delete the Job (and, if you like,
# this association by toggling the flag) after staging.
module "agw_demo_stager_pod_identity" {
  count   = var.enable_agw_demo ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name            = "agw-demo-model-stager"
  use_name_prefix = false

  additional_policy_arns = {
    models_stage = aws_iam_policy.agw_demo_models_stage[0].arn
  }

  associations = {
    agw_model_stager = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.agw_demo_namespace
      service_account = local.agw_demo_stager_sa
    }
  }

  tags = local.agw_demo_tags
}

#---------------------------------------------------------------
# Kubernetes: namespace, ServiceAccounts, Valkey Secret
#---------------------------------------------------------------
resource "kubectl_manifest" "agw_demo_namespace" {
  count = var.enable_agw_demo ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${local.agw_demo_namespace}
      labels:
        project: agw-demo
        owner: vara
  YAML

  depends_on = [module.eks]
}

resource "kubectl_manifest" "agw_demo_service_accounts" {
  for_each = var.enable_agw_demo ? toset([local.agw_demo_ray_sa, local.agw_demo_stager_sa]) : toset([])

  yaml_body = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: ${each.value}
      namespace: ${local.agw_demo_namespace}
      labels:
        project: agw-demo
  YAML

  depends_on = [kubectl_manifest.agw_demo_namespace]
}

# KubeRay gcsFaultToleranceOptions reads the address and password from here.
resource "kubernetes_secret" "agw_demo_valkey" {
  count = var.enable_agw_demo ? 1 : 0

  metadata {
    name      = local.agw_demo_valkey_secret
    namespace = local.agw_demo_namespace
    labels = {
      project = "agw-demo"
    }
  }

  data = {
    # rediss:// = TLS (transit encryption is required on this group).
    address  = "rediss://${aws_elasticache_replication_group.agw_demo_valkey[0].primary_endpoint_address}:6379"
    password = random_password.agw_demo_valkey_auth[0].result
  }

  depends_on = [kubectl_manifest.agw_demo_namespace]
}

#---------------------------------------------------------------
# Teardown hook: makes `enable_agw_demo = false` safe on its own.
#
# The demo's RayServices and Gateway objects are applied with kubectl (from
# examples/agw-demo), so Terraform doesn't know about them. Without this hook,
# deleting the NodePools hangs forever: the gateway proxy pods (PDB
# minAvailable 2, pinned to agw-demo-cpu nodes) and Ray heads
# (karpenter.sh/do-not-disrupt) can never be evicted.
#
# This resource depends on the NodePools, namespace and Valkey, so Terraform
# destroys it FIRST; its destroy provisioner deletes those kubectl-managed
# objects, and the nodes then drain normally. Same steps as
# examples/agw-demo/cleanup.sh --yes (which you can still run beforehand).
#---------------------------------------------------------------
resource "terraform_data" "agw_demo_teardown" {
  count = var.enable_agw_demo ? 1 : 0

  # Destroy provisioners can only read self, so carry what they need here.
  input = {
    cluster = local.name
    region  = local.region
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      KC=$(mktemp)
      aws eks update-kubeconfig --name ${self.input.cluster} --region ${self.input.region} --kubeconfig "$KC" >/dev/null
      export KUBECONFIG="$KC"
      echo "agw-demo teardown: removing kubectl-managed demo objects before NodePools are deleted"
      # Gateway objects (all labelled project=agw-demo); deleting the Gateway removes the proxies + PDB.
      kubectl -n agentgateway-system delete agentgatewaypolicy,agentgatewaymodel,grpcroute -l project=agw-demo --ignore-not-found || true
      kubectl -n agentgateway-system delete gateway,agentgatewayparameters -l project=agw-demo --ignore-not-found --wait=true --timeout=180s || true
      kubectl -n agentgateway-system delete configmap -l project=agw-demo --ignore-not-found || true
      # Ray: deleting RayServices removes heads (do-not-disrupt) and GPU workers.
      kubectl -n agw-demo delete rayservice --all --ignore-not-found --wait=true --timeout=300s || true
      kubectl -n agw-demo delete job,pod --all --ignore-not-found --wait=false || true
      rm -f "$KC"
    EOT
  }

  depends_on = [
    kubectl_manifest.agw_demo_nodepool,
    kubectl_manifest.agw_demo_namespace,
    aws_elasticache_replication_group.agw_demo_valkey,
  ]
}

output "agw_demo" {
  description = "agw-demo base infrastructure"
  value = var.enable_agw_demo ? {
    namespace        = local.agw_demo_namespace
    models_uri       = "s3://${module.s3_bucket.s3_bucket_id}/${local.agw_demo_models_prefix}"
    valkey_primary   = aws_elasticache_replication_group.agw_demo_valkey[0].primary_endpoint_address
    valkey_secret    = local.agw_demo_valkey_secret
    ray_role_arn     = module.agw_demo_ray_pod_identity[0].iam_role_arn
    stager_role_arn  = module.agw_demo_stager_pod_identity[0].iam_role_arn
    gpu_zones        = local.agw_demo_gpu_zones
  } : null
}
