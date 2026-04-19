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
# S3 Files Resources via AWS CLI
# Workaround: aws_s3files_* resources require AWS provider v6+
# but upstream modules (EKS, eks-data-addons) are pinned to v5.x
# TODO: Replace with native Terraform resources when modules support v6
#---------------------------------------------------------------
locals {
  s3_files_output_dir = "${path.module}/.s3files"
}

resource "null_resource" "s3_files_create" {
  depends_on = [
    aws_iam_role.s3_files,
    aws_iam_role_policy.s3_files_bucket_access,
    aws_security_group.s3_files,
    module.vpc
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p ${local.s3_files_output_dir}

      echo "=== Creating S3 Files filesystem ==="
      FS_ID=$(aws s3files create-file-system \
        --bucket "${module.s3_bucket.s3_bucket_arn}" \
        --role-arn "${aws_iam_role.s3_files.arn}" \
        --region "${local.region}" \
        --query 'Id' --output text)
      echo -n $FS_ID > ${local.s3_files_output_dir}/fs_id.txt
      echo "Created filesystem: $FS_ID"

      echo "=== Waiting for filesystem to become available ==="
      for i in $(seq 1 30); do
        STATUS=$(aws s3files describe-file-system --file-system-id $FS_ID --region "${local.region}" --query 'Status' --output text 2>/dev/null || echo "CREATING")
        echo "  Status: $STATUS"
        if [ "$STATUS" = "AVAILABLE" ]; then break; fi
        sleep 10
      done

      echo "=== Creating mount target ==="
      MT_RESULT=$(aws s3files create-mount-target \
        --file-system-id "$FS_ID" \
        --subnet-id "${module.vpc.private_subnets[0]}" \
        --security-groups "${aws_security_group.s3_files.id}" \
        --region "${local.region}" \
        --output json)
      MT_ID=$(echo $MT_RESULT | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'])")
      MT_IP=$(echo $MT_RESULT | python3 -c "import sys,json; print(json.load(sys.stdin).get('Ipv4Address',''))")
      echo -n $MT_ID > ${local.s3_files_output_dir}/mt_id.txt
      echo -n $MT_IP > ${local.s3_files_output_dir}/mt_ip.txt
      echo "Created mount target: $MT_ID ($MT_IP)"

      echo "=== Waiting for mount target to become available ==="
      for i in $(seq 1 30); do
        STATUS=$(aws s3files describe-mount-targets --file-system-id $FS_ID --region "${local.region}" --query 'MountTargets[0].Status' --output text 2>/dev/null || echo "CREATING")
        echo "  Status: $STATUS"
        if [ "$STATUS" = "AVAILABLE" ]; then break; fi
        sleep 10
      done

      echo "=== Creating access point ==="
      AP_ID=$(aws s3files create-access-point \
        --file-system-id "$FS_ID" \
        --posix-user "Uid=185,Gid=185" \
        --region "${local.region}" \
        --query 'Id' --output text)
      echo -n $AP_ID > ${local.s3_files_output_dir}/ap_id.txt
      echo "Created access point: $AP_ID"

      echo "=== S3 Files setup complete ==="
      echo "Filesystem ID: $FS_ID"
      echo "Mount Target ID: $MT_ID"
      echo "Mount Target IP: $MT_IP"
      echo "Access Point ID: $AP_ID"
    EOT
  }
}

data "local_file" "s3_files_fs_id" {
  filename   = "${local.s3_files_output_dir}/fs_id.txt"
  depends_on = [null_resource.s3_files_create]
}

data "local_file" "s3_files_mt_ip" {
  filename   = "${local.s3_files_output_dir}/mt_ip.txt"
  depends_on = [null_resource.s3_files_create]
}

data "local_file" "s3_files_ap_id" {
  filename   = "${local.s3_files_output_dir}/ap_id.txt"
  depends_on = [null_resource.s3_files_create]
}

data "local_file" "s3_files_mt_id" {
  filename   = "${local.s3_files_output_dir}/mt_id.txt"
  depends_on = [null_resource.s3_files_create]
}

#---------------------------------------------------------------
# Native Terraform resources (requires AWS provider v6.40+)
# Uncomment when upstream modules support AWS provider v6
#---------------------------------------------------------------
# resource "aws_s3files_file_system" "spark_data" {
#   bucket   = module.s3_bucket.s3_bucket_arn
#   role_arn = aws_iam_role.s3_files.arn
#
#   tags = merge(
#     local.tags,
#     {
#       Name        = "${local.name}-s3-files"
#       Description = "S3 Files filesystem for Spark data access"
#       Purpose     = "SparkOnEKS"
#     }
#   )
# }
#
# resource "aws_s3files_mount_target" "spark_data" {
#   count = length(local.azs)
#
#   file_system_id  = aws_s3files_file_system.spark_data.id
#   subnet_id       = module.vpc.private_subnets[count.index]
#   security_groups = [aws_security_group.s3_files.id]
# }
#
# resource "aws_s3files_file_system_policy" "spark_data" {
#   file_system_id = aws_s3files_file_system.spark_data.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
#         }
#         Action   = "s3files:ClientMount"
#         Resource = "*"
#       }
#     ]
#   })
# }
#
# resource "aws_s3files_synchronization_configuration" "spark_data" {
#   file_system_id = aws_s3files_file_system.spark_data.id
#
#   import_data_rule {
#     prefix         = "order/"
#     size_less_than = 52673613135872
#     trigger        = "ON_FILE_ACCESS"
#   }
#
#   expiration_data_rule {
#     days_after_last_access = 30
#   }
# }
#
# resource "aws_s3files_access_point" "spark_team_a" {
#   file_system_id = aws_s3files_file_system.spark_data.id
#
#   posix_user {
#     gid = 185
#     uid = 185
#   }
#
#   tags = merge(
#     local.tags,
#     {
#       Name = "${local.name}-spark-team-a-ap"
#       Team = "spark-team-a"
#     }
#   )
# }
