module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # AWS Load Balancer Controller Add-on
  #---------------------------------------
  enable_aws_load_balancer_controller = true
  # turn off the mutating webhook for services because we are using
  # service.beta.kubernetes.io/aws-load-balancer-type: external
  aws_load_balancer_controller = {
    set = [{
      name  = "enableServiceMutatorWebhook"
      value = "false"
    }]
  }
  tags = local.tags
}

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
#   eks_addons = {
#     aws-ebs-csi-driver = {
#       service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
#     }
#     coredns    = {}
#     kube-proxy = {}
#     # VPC CNI uses worker node IAM role policies
#     vpc-cni = {}
#   }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
#   enable_metrics_server = true
#   metrics_server = {
#     timeout = "300"
#     values  = [templatefile("${path.module}/helm/metrics-server/values.yaml", {})]
#   }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
#   enable_cluster_autoscaler = true
#   cluster_autoscaler = {
#     timeout     = "300"
#     create_role = true
#     values = [templatefile("${path.module}/helm/cluster-autoscaler/values.yaml", {
#       aws_region     = var.region,
#       eks_cluster_id = module.eks.cluster_name
#     })]
#   }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
#   enable_karpenter                  = true
#   karpenter_enable_spot_termination = true
#   karpenter_node = {
#     iam_role_additional_policies = {
#       AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
#     }
#   }
#   karpenter = {
#     chart_version       = "0.37.0"
#     repository_username = data.aws_ecrpublic_authorization_token.token.user_name
#     repository_password = data.aws_ecrpublic_authorization_token.token.password
#   }

  #---------------------------------------
  # Prometheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Monitoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
#   enable_kube_prometheus_stack = true
#   kube_prometheus_stack = {
#     values        = [templatefile("${path.module}/helm/kube-prometheus-stack/values.yaml", {})]
#     chart_version = "48.1.1"
#     set_sensitive = [
#       {
#         name  = "grafana.adminPassword"
#         value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
#       }
#     ],
#   }
  #---------------------------------------
  # AWS for FluentBit
  #---------------------------------------
#   enable_aws_for_fluentbit = true
#   aws_for_fluentbit_cw_log_group = {
#     use_name_prefix   = false
#     name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
#     retention_in_days = 30
#   }
#   aws_for_fluentbit = {
#     values = [templatefile("${path.module}/helm/aws-for-fluentbit/values.yaml", {
#       region               = local.region,
#       cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
#       cluster_name         = module.eks.cluster_name
#     })]
#   }