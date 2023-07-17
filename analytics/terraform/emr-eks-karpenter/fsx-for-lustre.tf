#---------------------------------------------------------------
# FSx for Lustre File system Static provisioning
#    1> Create Fsx for Lustre filesystem (Lustre FS storage capacity must be 1200, 2400, or a multiple of 3600)
#    2> Create Storage Class for Filesystem (Cluster scoped)
#    3> Persistent Volume with  Hardcoded reference to Fsx for Lustre filesystem with filesystem_id and dns_name (Cluster scoped)
#    4> Persistent Volume claim for this persistent volume will always use the same file system (Namespace scoped)
#---------------------------------------------------------------
# NOTE: FSx for Lustre file system creation can take up to 10 mins
resource "aws_fsx_lustre_file_system" "this" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  deployment_type             = "PERSISTENT_2"
  storage_type                = "SSD"
  per_unit_storage_throughput = "500" # 125, 250, 500, 1000
  storage_capacity            = 2400

  subnet_ids         = [module.vpc.private_subnets[0]]
  security_group_ids = [aws_security_group.fsx[0].id]
  log_configuration {
    level = "WARN_ERROR"
  }
  tags = merge({ "Name" : "${local.name}-static" }, var.tags)
}

# This process can take upto 7 mins
resource "aws_fsx_data_repository_association" "this" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  file_system_id       = aws_fsx_lustre_file_system.this[0].id
  data_repository_path = "s3://${module.fsx_s3_bucket.s3_bucket_id}"
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
# Sec group for FSx for Lustre
#---------------------------------------------------------------
resource "aws_security_group" "fsx" {
  count = var.enable_fsx_for_lustre ? 1 : 0

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
module "fsx_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  create_bucket = var.enable_fsx_for_lustre

  bucket_prefix = "${local.name}-fsx-"
  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

#---------------------------------------------------------------
# Storage Class - FSx for Lustre
#---------------------------------------------------------------
resource "kubectl_manifest" "storage_class" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  yaml_body = templatefile("${path.module}/examples/fsx-for-lustre/fsxlustre-storage-class.yaml", {
    subnet_id         = module.vpc.private_subnets[0],
    security_group_id = aws_security_group.fsx[0].id
  })

  depends_on = [
    module.eks_blueprints_addons
  ]
}

#---------------------------------------------------------------
# FSx for Lustre Persistent Volume - Static provisioning
#---------------------------------------------------------------
resource "kubectl_manifest" "static_pv" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  yaml_body = templatefile("${path.module}/examples/fsx-for-lustre/fsx-static-pvc-shuffle-storage/fsxlustre-static-pv.yaml", {
    filesystem_id = aws_fsx_lustre_file_system.this[0].id,
    dns_name      = aws_fsx_lustre_file_system.this[0].dns_name
    mount_name    = aws_fsx_lustre_file_system.this[0].mount_name,
  })

  depends_on = [
    module.eks_blueprints_addons,
    kubectl_manifest.storage_class,
    aws_fsx_lustre_file_system.this
  ]
}
