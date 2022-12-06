#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.15.0"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access = true # if true, Kubernetes API requests within your cluster's VPC (such as node to control plane communication) use the private VPC endpoint
  cluster_endpoint_public_access  = true # if true, Your cluster API server is accessible from the internet. You can, optionally, limit the CIDR blocks that can access the public endpoint.

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Recommended outbound traffic for Node groups
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
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
    ingress_fsx1 = {
      description = "Allows Lustre traffic between Lustre clients"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
      from_port   = 1021
      to_port     = 1023
      protocol    = "tcp"
      type        = "ingress"
    }
    ingress_fsx2 = {
      description = "Allows Lustre traffic between Lustre clients"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
      from_port   = 988
      to_port     = 988
      protocol    = "tcp"
      type        = "ingress"
    }
  }

  managed_node_groups = {
    # Core node group for deploying all the critical add-ons
    mng1 = {
      node_group_name = "core-node-grp"
      subnet_ids      = module.vpc.private_subnets

      instance_types = ["m5.xlarge"]
      ami_type       = "AL2_x86_64"
      capacity_type  = "ON_DEMAND"

      disk_size = 100
      disk_type = "gp3"

      max_size               = 9
      min_size               = 3
      desired_size           = 3
      create_launch_template = true
      launch_template_os     = "amazonlinux2eks"

      update_config = [{
        max_unavailable_percentage = 50
      }]

      k8s_labels = {
        Environment   = "preprod"
        Zone          = "test"
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      additional_tags = {
        Name                                                             = "core-node-grp"
        subnet_type                                                      = "private"
        "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
        "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
        "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "core"
        "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
        "k8s.io/cluster-autoscaler/experiments"                          = "owned"
        "k8s.io/cluster-autoscaler/enabled"                              = "true"
      }
    },
    #---------------------------------------
    # Note: This example only uses ON_DEMAND node group for both Spark Driver and Executors.
    #   If you want to leverage SPOT nodes for Spark executors then create ON_DEMAND node group for placing your driver pods and SPOT nodegroup for executors.
    #   Use NodeSelectors to place your driver/executor pods with the help of Pod Templates.
    #---------------------------------------
    mng2 = {
      node_group_name = "spark-node-grp"
      subnet_ids      = module.vpc.private_subnets
      instance_types  = ["r5d.large"]
      ami_type        = "AL2_x86_64"
      capacity_type   = "ON_DEMAND"

      format_mount_nvme_disk = true # Mounts NVMe disks to /local1, /local2 etc. for multiple NVMe disks

      # RAID0 configuration is recommended for better performance when you use larger instances with multiple NVMe disks e.g., r5d.24xlarge
      # Permissions for hadoop user runs the spark job. user > hadoop:x:999:1000::/home/hadoop:/bin/bash
      post_userdata = <<-EOT
        #!/bin/bash
        set -ex
        /usr/bin/chown -hR +999:+1000 /local1
      EOT

      disk_size = 100
      disk_type = "gp3"

      max_size     = 9 # Managed node group soft limit is 450; request AWS for limit increase
      min_size     = 3
      desired_size = 3

      create_launch_template = true
      launch_template_os     = "amazonlinux2eks"

      update_config = [{
        max_unavailable_percentage = 50
      }]

      additional_iam_policies = []
      k8s_taints              = []

      k8s_labels = {
        Environment   = "preprod"
        Zone          = "test"
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "spark"
      }

      additional_tags = {
        Name                                                             = "spark-node-grp"
        subnet_type                                                      = "private"
        "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
        "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
        "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "spark"
        "k8s.io/cluster-autoscaler/node-template/label/disk"             = "nvme"
        "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
        "k8s.io/cluster-autoscaler/experiments"                          = "owned"
        "k8s.io/cluster-autoscaler/enabled"                              = "true"
      }
    },
  }

  #---------------------------------------
  # ENABLE EMR ON EKS
  # 1. Creates namespace
  # 2. k8s role and role binding(emr-containers user) for the above namespace
  # 3. IAM role for the team execution role
  # 4. Update AWS_AUTH config map with  emr-containers user and AWSServiceRoleForAmazonEMRContainers role
  # 5. Create a trust relationship between the job execution role and the identity of the EMR managed service account
  #---------------------------------------
  enable_emr_on_eks = true
  emr_on_eks_teams = {
    emr-data-team-a = {
      namespace               = "emr-data-team-a"
      job_execution_role      = "emr-eks-data-team-a"
      additional_iam_policies = [aws_iam_policy.emr_on_eks.arn]
    }
    emr-data-team-b = {
      namespace               = "emr-data-team-b"
      job_execution_role      = "emr-eks-data-team-b"
      additional_iam_policies = [aws_iam_policy.emr_on_eks.arn]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Example IAM policies for EMR job execution
#---------------------------------------------------------------
resource "aws_iam_policy" "emr_on_eks" {
  name        = format("%s-%s", local.name, "emr-job-iam-policies")
  description = "IAM policy for EMR on EKS Job execution"
  path        = "/"
  policy      = data.aws_iam_policy_document.emr_on_eks.json
}

#---------------------------------------------------------------
# Amazon Prometheus Workspace
#---------------------------------------------------------------
resource "aws_prometheus_workspace" "amp" {
  alias = format("%s-%s", "amp-ws", local.name)

  tags = local.tags
}

#---------------------------------------------------------------
# Create EMR on EKS Virtual Cluster
#---------------------------------------------------------------
resource "aws_emrcontainers_virtual_cluster" "this" {
  name = format("%s-%s", module.eks_blueprints.eks_cluster_id, "emr-data-team-a")

  container_provider {
    id   = module.eks_blueprints.eks_cluster_id
    type = "EKS"

    info {
      eks_info {
        namespace = "emr-data-team-a"
      }
    }
  }
  depends_on = [
    module.eks_blueprints_kubernetes_addons
  ]
}

#---------------------------------------------------------------
# FSx for Lustre File system Static provisioning
#    1> Create Fsx for Lustre filesystem (Lustre FS storage capacity must be 1200, 2400, or a multiple of 3600)
#    2> Create Storage Class for Filesystem (Cluster scoped)
#    3> Persistent Volume with  Hardcoded reference to Fsx for Lustre filesystem with filesystem_id and dns_name (Cluster scoped)
#    4> Persistent Volume claim for this persistent volume will always use the same file system (Namespace scoped)
#---------------------------------------------------------------
# NOTE: FSx for Lustre file system creation can take up to 10 mins
resource "aws_fsx_lustre_file_system" "this" {
  deployment_type             = "PERSISTENT_2"
  storage_type                = "SSD"
  per_unit_storage_throughput = "500" # 125, 250, 500, 1000
  storage_capacity            = 2400

  subnet_ids         = [module.vpc.private_subnets[0]]
  security_group_ids = [aws_security_group.fsx.id]
  log_configuration {
    level = "WARN_ERROR"
  }
  tags = merge({ "Name" : "${local.name}-static" }, local.tags)
}

resource "aws_fsx_data_repository_association" "example" {
  file_system_id       = aws_fsx_lustre_file_system.this.id
  data_repository_path = "s3://${aws_s3_bucket.this.id}"
  file_system_path     = "/data" # This directory will be used in Spark podTemplates under volumeMounts as subPath

  s3 {
    auto_export_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }

    auto_import_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
  }
}

#---------------------------------------------------------------
# Storage Class - FSx for Lustre
#---------------------------------------------------------------
resource "kubectl_manifest" "storage_class" {
  yaml_body = templatefile("${path.module}/fsx_lustre/fsxlustre-storage-class.yaml", {
    storage_class_name = local.storage_class_name,
    subnet_id          = module.vpc.private_subnets[0],
    security_group_id  = aws_security_group.fsx.id
  })

  depends_on = [
    module.eks_blueprints_kubernetes_addons
  ]
}

#---------------------------------------------------------------
# FSx for Lustre Persistent Volume - Static provisioning
#---------------------------------------------------------------
resource "kubectl_manifest" "static_pv" {
  yaml_body = templatefile("${path.module}/fsx_lustre/fsxlustre-static-pv.yaml", {
    pv_name            = "fsx-static-pv",
    filesystem_id      = aws_fsx_lustre_file_system.this.id,
    dns_name           = aws_fsx_lustre_file_system.this.dns_name
    mount_name         = aws_fsx_lustre_file_system.this.mount_name,
    storage_class_name = local.storage_class_name,
    storage            = "1000Gi"
  })

  depends_on = [
    module.eks_blueprints_kubernetes_addons,
    kubectl_manifest.storage_class,
    aws_fsx_lustre_file_system.this
  ]
}

#---------------------------------------------------------------
# PVC for FSx Static Provisioning
#---------------------------------------------------------------
resource "kubectl_manifest" "static_pvc" {
  yaml_body = templatefile("${path.module}/fsx_lustre/fsxlustre-static-pvc.yaml", {
    namespace          = "emr-data-team-a"
    pvc_name           = "fsx-static-pvc",
    pv_name            = "fsx-static-pv",
    storage_class_name = local.storage_class_name,
    request_storage    = "1000Gi"
  })

  depends_on = [
    module.eks_blueprints_kubernetes_addons,
    kubectl_manifest.storage_class,
    aws_fsx_lustre_file_system.this
  ]
}

#---------------------------------------------------------------
# PVC for FSx Dynamic Provisioning
#   Note: There is no need to provision a FSx for Lustre file system in advance for Dynamic Provisioning like we did for static provisioning as shown above
#
# Prerequisite for this PVC:
#   1> FSx for Lustre StorageClass should exist
#   2> FSx for CSI driver is installed
# This resource will provision a new PVC for FSx for Lustre filesystem. FSx CSI driver will then create PV and FSx for Lustre Scratch1 FileSystem for this PVC.
#---------------------------------------------------------------
resource "kubectl_manifest" "dynamic_pvc" {
  yaml_body = templatefile("${path.module}/fsx_lustre/fsxlustre-dynamic-pvc.yaml", {
    namespace          = "emr-data-team-a", # EMR EKS Teams Namespace for job execution
    pvc_name           = "fsx-dynamic-pvc",
    storage_class_name = local.storage_class_name,
    request_storage    = "2000Gi"
  })

  depends_on = [
    module.eks_blueprints_kubernetes_addons,
    kubectl_manifest.storage_class
  ]
}

#---------------------------------------------------------------
# Sec group for FSx for Lustre
#---------------------------------------------------------------
resource "aws_security_group" "fsx" {
  name        = "${local.name}-fsx"
  description = "Allow inbound traffic from private subnets of the VPC to FSx filesystem"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 1021
    to_port     = 1023
    protocol    = "tcp"
  }
  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
  }
  tags = local.tags
}
#---------------------------------------------------------------
# S3 bucket for DataSync between FSx for Lustre and S3 Bucket
#---------------------------------------------------------------
#tfsec:ignore:aws-s3-enable-bucket-logging tfsec:ignore:aws-s3-enable-versioning
resource "aws_s3_bucket" "this" {
  bucket_prefix = format("%s-%s", "fsx", data.aws_caller_identity.current.account_id)
  tags          = local.tags
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  acl    = "private"
}

#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}
