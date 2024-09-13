# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

# Filter out local zones, which are not currently supported
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  cluster_name = "automq-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "automq-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  map_public_ip_on_launch = true

}


resource "aws_security_group" "allow_all" {
  name        = "automq_allow_all_sg"
  description = "Allow all inbound traffic"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}




module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }


  self_managed_node_groups = {
    automq_asg = {
      ami_type      = "AL2_x86_64"
      instance_type = "r6in.xlarge"

      min_size     = 5
      max_size     = 10
      desired_size = 5
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}


data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


resource "aws_iam_policy" "automq_policy" {
  name = "automq_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "aps:RemoteWrite",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.automqs3databucket.id}",
          "arn:aws:s3:::${aws_s3_bucket.automqs3databucket.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.automqs3opsbucket.id}",
          "arn:aws:s3:::${aws_s3_bucket.automqs3opsbucket.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.automqs3walbucket.id}",
          "arn:aws:s3:::${aws_s3_bucket.automqs3walbucket.id}/*",
          module.prometheus.workspace_arn,
        ]
      }

    ]
  })
}

# attach policy to eks auto create role arn (like ec2 instance profile)
resource "aws_iam_role_policy_attachment" "automq_policy_attachment" {
  role = module.eks.self_managed_node_groups.automq_asg.iam_role_name
  policy_arn = aws_iam_policy.automq_policy.arn
}




resource "aws_s3_bucket" "automqs3databucket" {
  bucket        = "automqs3databucket"
  force_destroy = true

  tags = {
    Name      = "automqs3databucket"
  }
}

resource "aws_s3_bucket" "automqs3opsbucket" {
  bucket        = "automqs3opsbucket"
  force_destroy = true

  tags = {
    Name      = "automqs3opsbucket"
  }
}

resource "aws_s3_bucket" "automqs3walbucket" {
  bucket        = "automqs3walbucket"
  force_destroy = true

  tags = {
    Name      = "automqs3walbucket"
  }
}


module "prometheus" {
  source = "terraform-aws-modules/managed-service-prometheus/aws"

  workspace_alias = "automq_prometheus"
}





