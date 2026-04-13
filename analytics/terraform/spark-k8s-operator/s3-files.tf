#---------------------------------------------------------------
# Amazon S3 Files - File System Interface to S3
#---------------------------------------------------------------
# S3 Files provides file system semantics (POSIX, NFS) on top of S3 data
# Reference: https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files.html

#---------------------------------------------------------------
# IAM Role for S3 Files Filesystem
#---------------------------------------------------------------
resource "aws_iam_role" "s3_files" {
  name_prefix = "${local.name}-s3-files-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "elasticfilesystem.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "s3_files_bucket_access" {
  name_prefix = "${local.name}-s3-files-bucket-"
  role        = aws_iam_role.s3_files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

#---------------------------------------------------------------
# S3 Files Filesystem
#---------------------------------------------------------------
resource "aws_s3files_file_system" "spark_data" {
  bucket   = module.s3_bucket.s3_bucket_arn
  role_arn = aws_iam_role.s3_files.arn

  tags = merge(
    local.tags,
    {
      Name        = "${local.name}-s3-files"
      Description = "S3 Files filesystem for Spark data access"
      Purpose     = "SparkOnEKS"
    }
  )
}

#---------------------------------------------------------------
# S3 Files Mount Targets - One per Availability Zone
#---------------------------------------------------------------
resource "aws_s3files_mount_target" "spark_data" {
  count = length(local.azs)

  file_system_id  = aws_s3files_file_system.spark_data.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.s3_files.id]
}

#---------------------------------------------------------------
# Security Group for S3 Files Access
#---------------------------------------------------------------
resource "aws_security_group" "s3_files" {
  name_prefix = "${local.name}-s3-files-"
  description = "Security group for S3 Files access from EKS nodes"
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
# S3 Files Filesystem Policy
#---------------------------------------------------------------
resource "aws_s3files_file_system_policy" "spark_data" {
  file_system_id = aws_s3files_file_system.spark_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "s3files:ClientMount"
        Resource = "*"
      }
    ]
  })
}

#---------------------------------------------------------------
# S3 Files Synchronization Configuration
#---------------------------------------------------------------
resource "aws_s3files_synchronization_configuration" "spark_data" {
  file_system_id = aws_s3files_file_system.spark_data.id

  # Import data from S3 to filesystem cache when accessed
  import_data_rule {
    prefix         = "order/"  # Only sync order data
    size_less_than = 52673613135872  # ~50TB limit
    trigger        = "ON_FILE_ACCESS"  # Load on-demand
  }

  # Expire data from cache after 30 days of no access
  expiration_data_rule {
    days_after_last_access = 30
  }
}

#---------------------------------------------------------------
# S3 Files Access Point for Spark Team A
#---------------------------------------------------------------
resource "aws_s3files_access_point" "spark_team_a" {
  file_system_id = aws_s3files_file_system.spark_data.id

  posix_user {
    gid = 185  # Spark user GID
    uid = 185  # Spark user UID
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-spark-team-a-ap"
      Team = "spark-team-a"
    }
  )
}
