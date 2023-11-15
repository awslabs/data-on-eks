# Use this data source to get the ARN of a certificate in AWS Certificate Manager (ACM)
data "aws_acm_certificate" "issued" {
  count    = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

locals {
  cognito_custom_domain = var.cognito_custom_domain
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.20"
  role_name_prefix      = format("%s-%s", local.name, "ebs-csi-driver-")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    timeout = "300"
    values = [templatefile("${path.module}/helm/coredns-autoscaler/values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    timeout = "300"
    values  = [templatefile("${path.module}/helm/metrics-server/values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    timeout     = "300"
    create_role = true
    values = [templatefile("${path.module}/helm/cluster-autoscaler/values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter = {
    timeout             = "300"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # AWS Load Balancer Controller
  #---------------------------------------
  enable_aws_load_balancer_controller = true

  #---------------------------------------
  # Prometheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Monitoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values        = [templatefile("${path.module}/helm/kube-prometheus-stack/values.yaml", {})]
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
  }
  #---------------------------------------
  # AWS for FluentBit
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    values = [templatefile("${path.module}/helm/aws-for-fluentbit/values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      cluster_name         = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Additional Helm Charts
  #---------------------------------------
  helm_releases = {
    storageclass = {
      name        = "storageclass"
      description = "A Helm chart for storage configurations"
      chart       = "${path.module}/helm/storageclass"
    }
    karpenter-resources-cpu = {
      name        = "karpenter-resources-cpu"
      description = "A Helm chart for karpenter CPU based resources"
      chart       = "${path.module}/helm/karpenter-resources"
      values = [
        <<-EOT
          clusterName: ${module.eks.cluster_name}
        EOT
      ]
    }
    karpenter-resources-ts = {
      name        = "karpenter-resources-ts"
      description = "A Helm chart for karpenter GPU based resources - compatible with GPU time slicing"
      chart       = "${path.module}/helm/karpenter-resources"
      values = [
        <<-EOT
          name: gpu-ts
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["xlarge", "2xlarge", "4xlarge", "8xlarge", "16xlarge", "24xlarge"]
          instanceFamilies: ["g5"]
          taints:
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
            - key: nvidia.com/gpu
              effect: "NoSchedule"
          amiFamily: Ubuntu
        EOT
      ]
    }
    karpenter-resources-mig = {
      name        = "karpenter-resources-gpu"
      description = "A Helm chart for karpenter GPU based resources - compatible with P4d instances"
      chart       = "${path.module}/helm/karpenter-resources"
      values = [
        <<-EOT
          name: gpu
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["24xlarge"]
          instanceFamilies: ["p4d"]
          taints:
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
            - key: nvidia.com/gpu
              effect: "NoSchedule"
          amiFamily: Ubuntu
        EOT
      ]
    }
    karpenter-resources-inf = {
      name        = "karpenter-resources-inf"
      description = "A Helm chart for karpenter Inferentia based resources"
      chart       = "${path.module}/helm/karpenter-resources"
      values = [
        <<-EOT
          name: inferentia
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["8xlarge", "24xlarge"]
          instanceFamilies: ["inf2"]
          taints:
            - key: aws.amazon.com/neuroncore
              value: "true"
              effect: "NoSchedule"
            - key: aws.amazon.com/neuron
              value: "true"
              effect: "NoSchedule"
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
        EOT
      ]
    }
    karpenter-resources-trn = {
      name        = "karpenter-resources-trn"
      description = "A Helm chart for karpenter Trainium based resources"
      chart       = "${path.module}/helm/karpenter-resources"
      values = [
        <<-EOT
          name: trainium
          clusterName: ${module.eks.cluster_name}
          instanceSizes: ["32xlarge"]
          instanceFamilies: ["trn1"]
          taints:
            - key: aws.amazon.com/neuroncore
              value: "true"
              effect: "NoSchedule"
            - key: aws.amazon.com/neuron
              value: "true"
              effect: "NoSchedule"
            - key: hub.jupyter.org/dedicated
              value: "user"
              effect: "NoSchedule"
        EOT
      ]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # Enable Neuron Device Plugin
  #---------------------------------------------------------------
  enable_aws_neuron_device_plugin = true

  #---------------------------------------------------------------
  # Enable GPU operator
  #---------------------------------------------------------------
  enable_nvidia_gpu_operator = true
  nvidia_gpu_operator_helm_config = {
    values = [templatefile("${path.module}/helm/nvidia-gpu-operator/values.yaml", {})]
  }

  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = true
  jupyterhub_helm_config = {
    values = [templatefile("${path.module}/helm/jupyterhub/jupyterhub-values-${var.jupyter_hub_auth_mechanism}.yaml", {
      ssl_cert_arn                = try(data.aws_acm_certificate.issued[0].arn, "")
      jupyterdomain               = try("https://${var.jupyterhub_domain}/hub/oauth_callback", "")
      authorize_url               = try("https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/authorize", "")
      token_url                   = try("https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/token", "")
      userdata_url                = try("https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/userInfo", "")
      client_id                   = try(aws_cognito_user_pool_client.user_pool_client[0].id, "")
      client_secret               = try(aws_cognito_user_pool_client.user_pool_client[0].client_secret, "")
      jupyter_single_user_sa_name = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
    })]
  }

  #---------------------------------------------------------------
  # Kubecost Add-on
  #---------------------------------------------------------------
  enable_kubecost = true
  kubecost_helm_config = {
    values              = [templatefile("${path.module}/helm/kubecost/values.yaml", {})]
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "grafana" {
  name_prefix             = "${local.name}-grafana-"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}
