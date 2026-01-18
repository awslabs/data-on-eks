

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = var.eks_cluster_version

  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  endpoint_public_access = var.cluster_endpoint_public_access

  # Add the IAM identity that terraform is using as a cluster admin
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  addons = local.eks_core_addons

  ip_family = var.enable_ipv6 ? "ipv6" : "ipv4"
  # Only create CNI IPv6 policy when IPv6 is enabled
  # Note: This creates a hardcoded policy named "AmazonEKS_CNI_IPv6_Policy" which will conflict
  # if multiple clusters are deployed in the same AWS account with IPv6 enabled
  create_cni_ipv6_iam_policy = var.enable_ipv6

  vpc_id = module.vpc.vpc_id
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
    substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
  )

  # Combine root account, current user/role and additional roles to be able to access the cluster KMS key - required for terraform updates
  kms_key_administrators = distinct(concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.kms_key_admin_roles,
    [data.aws_iam_session_context.current.issuer_arn]
  ))

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  # Extend cluster security group rules
  security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Merge the default node groups with user-provided node groups
  eks_managed_node_groups = merge(local.default_node_groups, var.managed_node_groups)
}

#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType             = "xfs"
    encrypted          = true
    type               = "gp3"
    tagSpecification_1 = "DeploymentId=${var.deployment_id}"
  }
}

#---------------------------------------------------------------
# ArgoCD Installation via Terraform
#---------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.1.1"
  namespace        = "argocd"
  create_namespace = true

  values = [
    templatefile("${path.module}/helm-values/argocd.yaml", {})
  ]

  depends_on = [aws_eks_addon.aws_ebs_csi_driver]
}

resource "kubectl_manifest" "quay_io_repo" {
  yaml_body = templatefile("${path.module}/manifests/argocd/quay-io-repo.yaml", {})

  depends_on = [
    helm_release.argocd
  ]
}

#---------------------------------------------------------------
# EKS Amazon CloudWatch Observability Role
#---------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_observability_role" {
  name = "${var.name}-eks-cw-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability_role.name
}

#-------------------------------------------------------
# EBS CSI Driver Pod Identity Role
#-------------------------------------------------------
resource "aws_iam_role" "ebs_csi_pod_identity_role" {
  name = "${var.name}-ebs-csi-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# Attach EBS CSI policy to the role
resource "aws_iam_role_policy_attachment" "ebs_csi_pod_identity_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_pod_identity_role.name
}

#-------------------------------------------------------
# Mountpoint for S3 CSI Driver Pod Identity Role
#-------------------------------------------------------
resource "aws_iam_role" "s3_csi_pod_identity_role" {
  name = "${var.name}-s3-csi-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# Attach S3 CSI policy to the role
resource "aws_iam_role_policy_attachment" "s3_csi_pod_identity_policy" {
  policy_arn = aws_iam_policy.s3_csi_access_policy.arn
  role       = aws_iam_role.s3_csi_pod_identity_role.name
}

#---------------------------------------------------------------
# S3 CSI Driver Policy (used by Pod Identity)
#---------------------------------------------------------------
resource "aws_iam_policy" "s3_csi_access_policy" {
  name        = "${var.name}-S3CSIAccess"
  path        = "/"
  description = "S3 CSI Driver Access Policy for standard S3 and S3 Express One Zone"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MountpointFullBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Sid    = "MountpointFullObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ExpressCreateSession"
        Effect = "Allow"
        Action = [
          "s3express:CreateSession"
        ]
        Resource = "arn:aws:s3express:${local.region}:${local.account_id}:bucket/*"
      }
    ]
  })
}

#---------------------------------------------------------------
# CNI IPv6 Policy
# Used by Karpenter nodes only currently. This will need to used by core node gorup as well once issues with create_cni_ipv6_iam_policy is resolved.
#---------------------------------------------------------------
resource "aws_iam_policy" "cni_ipv6_policy" {
  name_prefix = "${local.name}-cni-ipv6"
  path        = "/"
  description = "CNI IPv6 Policy for Karpenter Nodes"
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "ec2:DescribeTags",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:AssignIpv6Addresses"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "AssignDescribe"
      },
      {
        "Action" : "ec2:CreateTags",
        "Effect" : "Allow",
        "Resource" : "arn:aws:ec2:*:*:network-interface/*",
        "Sid" : "CreateTags"
      }
    ],
    "Version" : "2012-10-17"
  })
}
