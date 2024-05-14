#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "disable_gp2" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks.eks_cluster_id]
}

resource "kubernetes_storage_class" "default_gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "ext4"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.disable_gp2]
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.20"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
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
# EKS Blueprints Addons
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
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
    # VPC CNI uses worker node IAM role policies
    vpc-cni = {
      preserve = true
    }
  }

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

  #---------------------------------------
  # Ingress Nginx Add-on
  #---------------------------------------
  enable_ingress_nginx = true
  ingress_nginx = {
    values = [templatefile("${path.module}/helm-values/ingress-nginx-values.yaml", {})]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  karpenter = {
    chart_version       = "v0.34.0"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # Argo Workflows & Argo Events
  #---------------------------------------
  enable_argo_workflows = true
  argo_workflows = {
    name       = "argo-workflows"
    namespace  = "argo-workflows"
    repository = "https://argoproj.github.io/argo-helm"
    values     = [templatefile("${path.module}/helm-values/argo-workflows-values.yaml", {})]
  }

  enable_argo_events = true
  argo_events = {
    name       = "argo-events"
    namespace  = "argo-events"
    repository = "https://argoproj.github.io/argo-helm"
    values     = [templatefile("${path.module}/helm-values/argo-events-values.yaml", {})]
  }

}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.31.4" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = true
  jupyterhub_helm_config = {
    namespace        = kubernetes_namespace_v1.jupyterhub.id
    create_namespace = false
    values           = [file("${path.module}/helm-values/jupyterhub-values.yaml")]
  }

  enable_volcano = true
  #---------------------------------------
  # Kuberay Operator
  #---------------------------------------
  enable_kuberay_operator = true
  kuberay_operator_helm_config = {
    version = "1.1.0"
    # Enabling Volcano as Batch scheduler for KubeRay Operator
    values = [
      <<-EOT
      batchScheduler:
        enabled: true
    EOT
    ]
  }

  #---------------------------------------------------------------
  # NVIDIA Device Plugin Add-on
  #---------------------------------------------------------------
  enable_nvidia_device_plugin = true
  nvidia_device_plugin_helm_config = {
    version = "v0.14.5"
    name    = "nvidia-device-plugin"
    values = [
      <<-EOT
        gfd:
          enabled: true
        nfd:
          worker:
            tolerations:
              - key: nvidia.com/gpu
                operator: Exists
                effect: NoSchedule
              - operator: "Exists"
      EOT
    ]
  }

  #---------------------------------------
  # EFA Device Plugin Add-on
  #---------------------------------------
  # IMPORTANT: Enable EFA only on nodes with EFA devices attached.
  # Otherwise, you'll encounter the "No devices found..." error. Restart the pod after attaching an EFA device, or use a node selector to prevent incompatible scheduling.
  enable_aws_efa_k8s_device_plugin = var.enable_aws_efa_k8s_device_plugin
  aws_efa_k8s_device_plugin_helm_config = {
    values = [file("${path.module}/helm-values/aws-efa-k8s-device-plugin-values.yaml")]
  }

  #---------------------------------------------------------------
  # Kubecost Add-on
  #---------------------------------------------------------------
  enable_kubecost = var.enable_kubecost
  kubecost_helm_config = {
    values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
    version             = "2.2.2"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------------------------------
  # Karpenter Resources Add-on
  #---------------------------------------------------------------
  enable_karpenter_resources = true
  karpenter_resources_helm_config = {
    g5-gpu-karpenter = {
      values = [
        <<-EOT
      name: g5-gpu-karpenter
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          id: ${module.vpc.private_subnets[2]}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: g5-gpu-karpenter
        taints:
          - key: nvidia.com/gpu
            value: "Exists"
            effect: "NoSchedule"
        requirements:
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["g5"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: [ "2xlarge", "4xlarge", "8xlarge"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 180s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
    x86-cpu-karpenter = {
      values = [
        <<-EOT
      name: x86-cpu-karpenter
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          id: ${module.vpc.private_subnets[3]}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: x86-cpu-karpenter
        requirements:
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["m5"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: [ "xlarge", "2xlarge", "4xlarge", "8xlarge"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 180s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
  }

  depends_on = [
    kubernetes_secret_v1.huggingface_token,
    kubernetes_config_map_v1.notebook
  ]
}


#---------------------------------------------------------------
# Additional Resources
#---------------------------------------------------------------

resource "kubernetes_namespace_v1" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}


resource "kubernetes_secret_v1" "huggingface_token" {
  metadata {
    name      = "hf-token"
    namespace = kubernetes_namespace_v1.jupyterhub.id
  }

  data = {
    token = var.huggingface_token
  }
}

resource "kubernetes_config_map_v1" "notebook" {
  metadata {
    name      = "notebook"
    namespace = kubernetes_namespace_v1.jupyterhub.id
  }

  data = {
    "dogbooth.ipynb" = file("${path.module}/src/notebook/dogbooth.ipynb")
  }
}
