
###############################################################################
# AWS Batch On-Demand EC2 compute environment
###############################################################################
resource "aws_batch_compute_environment" "doeks_ondemand_ce" {
  compute_environment_name = join("_", [var.aws_batch_doeks_ce_name, "OD"])
  type                     = "MANAGED"
  state                    = "ENABLED"

  eks_configuration {
    eks_cluster_arn      = module.eks.cluster_arn
    kubernetes_namespace = "doeks-aws-batch"
  }

  compute_resources {
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"

    min_vcpus = var.aws_batch_min_vcpus
    max_vcpus = var.aws_batch_max_vcpus

    instance_type = var.aws_batch_instance_types
    instance_role = aws_iam_instance_profile.batch_eks_instance_profile.arn

    security_group_ids = [
      module.eks.node_security_group_id
    ]
    subnets = tolist(module.vpc.private_subnets)
  }

  depends_on = [
    module.eks,
    module.eks_auth,
    kubernetes_namespace.doeks_batch_namespace,
    kubernetes_role_binding.batch_compute_env_role_binding,
    kubernetes_cluster_role_binding.batch_cluster_role_binding,
    aws_iam_instance_profile.batch_eks_instance_profile
  ]
}

###############################################################################
# AWS Batch Spot EC2 compute environment
###############################################################################

resource "aws_batch_compute_environment" "doeks_spot_ce" {
  compute_environment_name = join("_", [var.aws_batch_doeks_ce_name, "SPOT"])
  type                     = "MANAGED"
  state                    = "ENABLED"

  eks_configuration {
    eks_cluster_arn      = module.eks.cluster_arn
    kubernetes_namespace = "doeks-aws-batch"
  }

  compute_resources {
    type                = "SPOT"
    allocation_strategy = "SPOT_PRICE_CAPACITY_OPTIMIZED"

    min_vcpus = var.aws_batch_min_vcpus
    max_vcpus = var.aws_batch_max_vcpus

    instance_type = var.aws_batch_instance_types
    instance_role = aws_iam_instance_profile.batch_eks_instance_profile.arn

    security_group_ids = [
      module.eks.node_security_group_id
    ]
    subnets = tolist(module.vpc.private_subnets)
  }

  depends_on = [
    module.eks,
    module.eks_auth,
    kubernetes_namespace.doeks_batch_namespace,
    kubernetes_role_binding.batch_compute_env_role_binding,
    kubernetes_cluster_role_binding.batch_cluster_role_binding,
    aws_iam_instance_profile.batch_eks_instance_profile
  ]
}
###############################################################################
# AWS Batch On-Demand Job Queue
###############################################################################
resource "aws_batch_job_queue" "doeks_ondemand_jq" {
  name     = join("_", [var.aws_batch_doeks_jq_name, "OD"])
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.doeks_ondemand_ce.arn
  }
  depends_on = [aws_batch_compute_environment.doeks_ondemand_ce]
}

###############################################################################
# AWS Batch Spot Job Queue
###############################################################################
resource "aws_batch_job_queue" "doeks_spot_jq" {
  name     = join("_", [var.aws_batch_doeks_jq_name, "SPOT"])
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.doeks_spot_ce.arn
  }
  depends_on = [aws_batch_compute_environment.doeks_spot_ce]
}


###############################################################################
# Batch Job Definition
###############################################################################
resource "aws_batch_job_definition" "doeks_hello_world" {
  name = var.aws_batch_doeks_jd_name
  type = "container"
  eks_properties {
    pod_properties {
      host_network = true
      containers {
        name  = "application-hello"
        image = "public.ecr.aws/amazonlinux/amazonlinux:2023"
        command = [
          "/bin/sh", "-c",
          "sleep 30 && echo 'Hello World!'"
        ]
        resources {
          limits = {
            cpu    = "1"
            memory = "1024Mi"
          }
        }
      }
      metadata {
        labels = {
          environment = "data-on-eks-sample"
        }
      }
    }
  }
}
