#---------------------------------------------------------------
# Amazon S3 Files - File System Interface to S3
# Uses CloudFormation to avoid null_resource/CLI workarounds
#---------------------------------------------------------------

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
          "s3:HeadObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:GetObjectVersion",
          "s3:ListBucketVersions"
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

  tags = merge(local.tags, { Name = "${local.name}-s3-files-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

#---------------------------------------------------------------
# Step 1: CloudFormation stack for S3 Files FileSystem only
# CFN waits for the filesystem to reach AVAILABLE before completing
#---------------------------------------------------------------
resource "aws_cloudformation_stack" "s3_files_fs" {
  name = "${local.name}-s3-files-fs"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "S3 Files filesystem for Spark on EKS"

    Resources = {
      FileSystem = {
        Type = "AWS::S3Files::FileSystem"
        Properties = {
          Bucket  = module.s3_bucket.s3_bucket_arn
          RoleArn = aws_iam_role.s3_files.arn
          Tags = [
            { Key = "Name", Value = "${local.name}-s3-files" },
            { Key = "Blueprint", Value = local.name }
          ]
        }
      }
    }

    Outputs = {
      FileSystemId = {
        Value = { "Fn::GetAtt" = ["FileSystem", "FileSystemId"] }
      }
    }
  })

  depends_on = [
    aws_iam_role_policy.s3_files_bucket_access,
    module.s3_bucket
  ]

  tags = local.tags
}

#---------------------------------------------------------------
# Step 2: CloudFormation stack for MountTarget + AccessPoint
# Only created after filesystem stack completes (filesystem is AVAILABLE)
#---------------------------------------------------------------
resource "aws_cloudformation_stack" "s3_files_resources" {
  name = "${local.name}-s3-files-resources"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "S3 Files mount target, access point, and filesystem policy for Spark on EKS"

    Resources = {
      FileSystemPolicy = {
        Type = "AWS::S3Files::FileSystemPolicy"
        Properties = {
          FileSystemId = aws_cloudformation_stack.s3_files_fs.outputs["FileSystemId"]
          Policy = {
            Version = "2012-10-17"
            Statement = [
              {
                Effect    = "Allow"
                Principal = { AWS = "*" }
                Action = [
                  "s3files:ClientMount",
                  "s3files:ClientWrite",
                  "s3files:ClientRootAccess"
                ]
                Resource = "*"
              }
            ]
          }
        }
      }

      MountTarget = {
        Type = "AWS::S3Files::MountTarget"
        Properties = {
          FileSystemId   = aws_cloudformation_stack.s3_files_fs.outputs["FileSystemId"]
          SubnetId       = module.vpc.private_subnets[0]
          SecurityGroups = [aws_security_group.s3_files.id]
        }
      }

      AccessPoint = {
        Type      = "AWS::S3Files::AccessPoint"
        DependsOn = "FileSystemPolicy"
        Properties = {
          FileSystemId = aws_cloudformation_stack.s3_files_fs.outputs["FileSystemId"]
          PosixUser = {
            Uid = "0"
            Gid = "0"
          }
          Tags = [
            { Key = "Name", Value = "${local.name}-spark-team-a-ap" },
            { Key = "Team", Value = "spark-team-a" }
          ]
        }
      }
    }

    Outputs = {
      MountTargetId = {
        Value = { "Fn::GetAtt" = ["MountTarget", "MountTargetId"] }
      }
      AccessPointId = {
        Value = { "Fn::GetAtt" = ["AccessPoint", "AccessPointId"] }
      }
    }
  })

  depends_on = [aws_cloudformation_stack.s3_files_fs]

  tags = local.tags
}

#---------------------------------------------------------------
# Look up mount target IP after creation
# (Ipv4Address is not a CFN GetAtt attribute for MountTarget)
#---------------------------------------------------------------
data "external" "s3_files_mount_target_ip" {
  program = ["bash", "-c", <<-EOT
    MT_ID="${aws_cloudformation_stack.s3_files_resources.outputs["MountTargetId"]}"
    IP=$(aws s3files get-mount-target --mount-target-id "$MT_ID" --region "${local.region}" --query 'ipv4Address' --output text)
    echo "{\"ip\": \"$IP\"}"
  EOT
  ]

  depends_on = [aws_cloudformation_stack.s3_files_resources]
}
