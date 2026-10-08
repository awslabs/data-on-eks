resource "aws_eks_addon" "aws_ebs_csi_driver" {
  count = var.enable_cluster_addons["aws-ebs-csi-driver"] ? 1 : 0

  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi_pod_identity_role.arn
    service_account = "ebs-csi-controller-sa"
  }
}

resource "aws_eks_addon" "metrics_server" {
  count = var.enable_cluster_addons["metrics-server"] ? 1 : 0

  cluster_name = module.eks.cluster_name
  addon_name   = "metrics-server"
}

resource "aws_eks_addon" "eks_node_monitoring_agent" {
  count = var.enable_cluster_addons["eks-node-monitoring-agent"] ? 1 : 0

  cluster_name = module.eks.cluster_name
  addon_name   = "eks-node-monitoring-agent"
}

resource "aws_eks_addon" "amazon_cloudwatch_observability" {
  count = var.enable_cluster_addons["amazon-cloudwatch-observability"] ? 1 : 0

  cluster_name = module.eks.cluster_name
  addon_name   = "amazon-cloudwatch-observability"

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch_observability_role.arn
    service_account = "cloudwatch-agent"
  }
}

resource "aws_eks_addon" "aws_mountpoint_s3_csi_driver" {
  count = var.enable_cluster_addons["aws-mountpoint-s3-csi-driver"] ? 1 : 0

  cluster_name = module.eks.cluster_name
  addon_name   = "aws-mountpoint-s3-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.s3_csi_pod_identity_role.arn
    service_account = "s3-csi-driver-sa"
  }
}
