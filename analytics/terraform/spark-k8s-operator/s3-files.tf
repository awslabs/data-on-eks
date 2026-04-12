#---------------------------------------------------------------
# Amazon S3 Files - File System Interface to S3
#---------------------------------------------------------------
# S3 Files provides file system semantics (POSIX, NFS) on top of S3 data
# Built on EFS technology with intelligent caching
# Reference: https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files.html

resource "aws_efs_file_system" "s3_files" {
  creation_token = "${local.name}-s3-files"

  # Performance mode
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  # Encryption at rest
  encrypted  = true
  kms_key_id = null # Uses AWS managed key. Set to aws_kms_key.this.arn for customer-managed key

  # Lifecycle management for cost optimization
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  # Link to S3 bucket for S3 Files functionality
  # NOTE: As of the latest AWS API, S3 Files is configured via the AWS Console or CLI
  # This creates the EFS filesystem that can be configured as S3 Files post-deployment
  # Follow AWS documentation to link this filesystem to your S3 bucket

  tags = merge(
    local.tags,
    {
      Name        = "${local.name}-s3-files"
      Description = "EFS filesystem for S3 Files - provides file system interface to S3 data"
      Purpose     = "SparkOnEKS"
    }
  )
}

#---------------------------------------------------------------
# EFS Mount Targets - One per Availability Zone
#---------------------------------------------------------------
resource "aws_efs_mount_target" "s3_files" {
  count = length(local.azs)

  file_system_id = aws_efs_file_system.s3_files.id
  # Mount in primary private subnets (10.x CIDR range)
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.s3_files.id]
}

#---------------------------------------------------------------
# Security Group for S3 Files / EFS Access
#---------------------------------------------------------------
resource "aws_security_group" "s3_files" {
  name_prefix = "${local.name}-s3-files-"
  description = "Security group for S3 Files (EFS) access from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "NFS from VPC CIDR blocks"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = concat(
      [module.vpc.vpc_cidr_block],
      module.vpc.vpc_secondary_cidr_blocks
    )
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-s3-files-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#---------------------------------------------------------------
# EFS Access Point for Spark Team A (Optional - for better isolation)
#---------------------------------------------------------------
resource "aws_efs_access_point" "spark_team_a" {
  file_system_id = aws_efs_file_system.s3_files.id

  posix_user {
    gid = 185 # Spark user GID
    uid = 185 # Spark user UID
  }

  root_directory {
    path = "/spark-team-a"
    creation_info {
      owner_gid   = 185
      owner_uid   = 185
      permissions = "755"
    }
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-spark-team-a-ap"
      Team = "spark-team-a"
    }
  )
}
