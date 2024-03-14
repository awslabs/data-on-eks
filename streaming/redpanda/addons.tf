
################################################################################
# EKS  Addons
################################################################################
#---------------------------------------------------------------
# IRSA
#---------------------------------------------------------------

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}
#---------------------------------------------------------------
# GP2 to GP3 default storage class and config for Redpanda
#---------------------------------------------------------------
resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}


#---------------------------------------------------------------
# EKS Blueprints Kubernetes Addons
#---------------------------------------------------------------
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
      most_recent = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }
  enable_aws_load_balancer_controller    = true
  enable_cluster_autoscaler              = true
  enable_metrics_server                  = true
  enable_aws_cloudwatch_metrics          = true

 

  #---------------------------------------
  # FluentBit Config for EKS Cluster
  #---------------------------------------
 enable_aws_for_fluentbit = true
  aws_for_fluentbit = {
    enable_containerinsights = true
    kubelet_monitoring       = true
    set = [{
        name  = "cloudWatchLogs.autoCreateGroup"
        value = true
      },
      {
        name  = "hostNetwork"
        value = true
      },
      {
        name  = "dnsPolicy"
        value = "ClusterFirstWithHostNet"
      }
    ]
  }


  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Kafka Montoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/templates/kube-prometheus-amp-enable.yaml", {
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
        storage_class_type  = kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class.id
      }) : templatefile("${path.module}/templates/kube-prometheus.yaml", {})
    ]
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.grafana_password_version.secret_string
      }
    ],
  }

  tags = local.tags
}

 ## Cert-Manager Config
  resource "helm_release" "cert-manager" {
    name = "cert-manager"
    repository = "https://charts.jetstack.io"
    chart = "cert-manager"
    version = "1.14.2"
    namespace = "cert-manager"
    create_namespace = true
    set {
     name = "installCRDs"
     value = true 
    }
    depends_on = [ module.eks_blueprints_addons ]
  }
  
  ## Redpanda Helm Config
resource "helm_release" "redpanda" {
    name = "redpanda"
    repository = "https://charts.redpanda.com"
    chart = "redpanda"
    version = "5.7.22"
    namespace = "redpanda"
    create_namespace = true

    values = [
        templatefile("${path.module}/templates/redpanda_values.yaml", {
        redpanda_username = var.redpanda_username,
        redpanda_password = data.aws_secretsmanager_secret_version.redpanada_password_version.secret_string,
        redpanda_domain = var.redpanda_domain,
        storage_class = "gp3"
         })
    ]
    #timeout = "3600"
    depends_on = [ helm_release.cert-manager ]
    }