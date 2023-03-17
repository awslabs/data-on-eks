locals {
  storage_class_name = "fsx"
}
data "aws_caller_identity" "current" {}
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

  subnet_ids         = [var.private_subnet] # [module.vpc.private_subnets[0]]
  security_group_ids = [aws_security_group.fsx.id]
  log_configuration {
    level = "WARN_ERROR"
  }
  tags = merge({ "Name" : "${var.cluster_name}-static" }, var.tags)
}

resource "aws_fsx_data_repository_association" "this" {
  file_system_id       = aws_fsx_lustre_file_system.this.id
  data_repository_path = "s3://${module.s3_bucket.s3_bucket_id}"
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
    subnet_id          = var.private_subnet, #module.vpc.private_subnets[0]
    security_group_id  = aws_security_group.fsx.id
  })
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
    kubectl_manifest.storage_class
  ]
}

#---------------------------------------------------------------
# Sec group for FSx for Lustre
#---------------------------------------------------------------
resource "aws_security_group" "fsx" {
  name        = "${var.cluster_name}-fsx"
  description = "Allow inbound traffic from private subnets of the VPC to FSx filesystem"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = var.private_subnets_cidr_blocks
    from_port   = 1021
    to_port     = 1023
    protocol    = "tcp"
  }
  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = var.private_subnets_cidr_blocks
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
  }
  tags = var.tags
}
#---------------------------------------------------------------
# S3 bucket for DataSync between FSx for Lustre and S3 Bucket
#---------------------------------------------------------------
#tfsec:ignore:aws-s3-enable-bucket-logging tfsec:ignore:aws-s3-enable-versioning
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "v3.3.0"

  bucket_prefix = format("%s-%s", "fsx", data.aws_caller_identity.current.account_id)
  acl           = "private"

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
}
