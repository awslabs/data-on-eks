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

resource "kubernetes_storage_class_v1" "default_gp3" {
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
    fsType    = "xfs"
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
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {})]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  # NOTE: Karpenter Upgrade
  # This Helm Chart addon will only install the CRD during the first installation of the helm chart.
  #  Subsequent Helm Chart chart upgrades will not add or remove CRDs, even if the CRDs have changed.
  #  If you need to upgrade the CRDs, you will need to manually run the following commands and ensure that the CRDs are updated before upgrading the Helm Chart.
  #  READ the guide before applying the CRDs: https://karpenter.sh/preview/upgrade-guide/
  # kubectl apply -f https://raw.githubusercontent.com/aws/karpenter/main/pkg/apis/crds/karpenter.sh_provisioners.yaml
  # kubectl apply -f https://raw.githubusercontent.com/aws/karpenter/main/pkg/apis/crds/karpenter.sh_machines.yaml
  # kubectl apply -f https://raw.githubusercontent.com/aws/karpenter/main/pkg/apis/crds/karpenter.k8s.aws_awsnodetemplates.yaml
  #---------------------------------------
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
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    values = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  #---------------------------------------
  # Enable FSx for Lustre CSI Driver
  #---------------------------------------
  enable_aws_fsx_csi_driver = true
  aws_fsx_csi_driver = {
    # INFO: fsx node daemonset won't be placed on Karpenter nodes with taints without the following toleration
    values = [
      <<-EOT
        node:
          tolerations:
            - operator: Exists
      EOT
    ]
  }

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    s3_bucket_arns = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*}"
    ]
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id kafka-on-eks-grafana --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
        storage_class_type  = kubernetes_storage_class_v1.default_gp3.id
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
        }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {
        storage_class_type = kubernetes_storage_class_v1.default_gp3.id
      })
    ]
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
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

  tags = local.tags

  # We are installing Karpenter resources with Helm Chart, see helm-values/

}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.30" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_neuron_device_plugin  = true
  enable_aws_efa_k8s_device_plugin = true
  #---------------------------------------
  # Volcano Scheduler for TorchX used in BERT-Large distributed training example
  # Volcano is also a default scheduler for KubeRay Operator
  #---------------------------------------
  enable_volcano = true

  #---------------------------------------
  # Kuberay Operator
  #---------------------------------------
  enable_kuberay_operator = true
  kuberay_operator_helm_config = {
    version = "1.0.0"
    # Enabling Volcano as Batch scheduler for KubeRay Operator
    values = [
      <<-EOT
      batchScheduler:
        enabled: true
    EOT
    ]
  }

  #---------------------------------------
  # JupyterHub Addon
  #---------------------------------------
  enable_jupyterhub = var.enable_jupyterhub
  jupyterhub_helm_config = {
    values = [
      templatefile("${path.module}/helm-values/jupyterhub-values.yaml", {
        jupyter_single_user_sa_name = "${module.eks.cluster_name}-jupyterhub-single-user"
      })
    ]
  }

  #---------------------------------------
  # Deploying Karpenter resources(Nodepool and NodeClass) with Helm Chart
  #---------------------------------------
  enable_karpenter_resources = true
  # We use index 2 to select the subnet in AZ1 with the 100.x CIDR:
  #   module.vpc.private_subnets = [AZ1_10.x, AZ2_10.x, AZ1_100.x, AZ2_100.x]
  karpenter_resources_helm_config = {
    inferentia-inf2 = {
      values = [
        <<-EOT
      name: inferentia-inf2
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          id: ${module.vpc.private_subnets[2]}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        blockDevice:
          deviceName: /dev/xvda
          volumeSize: 500Gi
          volumeType: gp3
          encrypted: true
          deleteOnTermination: true
      nodePool:
        labels:
          - instanceType: inferentia-inf2
          - provisionerType: Karpenter
          - hub.jupyter.org/node-purpose: user
        taints:
          - key: aws.amazon.com/neuroncore
            value: "true"
            effect: "NoSchedule"
          - key: aws.amazon.com/neuron
            value: "true"
            effect: "NoSchedule"
          - key: hub.jupyter.org/dedicated # According to optimization docs https://z2jh.jupyter.org/en/latest/administrator/optimization.html
            operator: "Equal"
            value: "user"
            effect: "NoSchedule"
        requirements:
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["inf2"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: ["24xlarge", "48xlarge"]
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
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
    default = {
      values = [
        <<-EOT
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          id: ${module.vpc.private_subnets[2]}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
          blockDevice:
            deviceName: /dev/xvda
            volumeSize: 200Gi
            volumeType: gp3
            encrypted: true
            deleteOnTermination: true
      nodePool:
        labels:
          - instanceType: mixed-x86
          - provisionerType: Karpenter
          - workload: rayhead
        requirements:
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5", "m5", "r5"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: ["xlarge", "2xlarge", "4xlarge", "8xlarge", "16xlarge", "24xlarge"]
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
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
  }
}

#---------------------------------------------------------------
# ETCD for TorchX
#---------------------------------------------------------------
data "http" "torchx_etcd_yaml" {
  url = "https://raw.githubusercontent.com/pytorch/torchx/main/resources/etcd.yaml"
}

data "kubectl_file_documents" "torchx_etcd_yaml" {
  content = data.http.torchx_etcd_yaml.response_body
}

resource "kubectl_manifest" "torchx_etcd" {
  for_each   = data.kubectl_file_documents.torchx_etcd_yaml.manifests
  yaml_body  = each.value
  depends_on = [module.eks.eks_cluster_id]
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
# Login to AWS secrets manager with the same role as Terraform to extract the Grafana admin password with the secret name as "grafana"
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
  name_prefix             = "${local.name}-oss-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-logs-"
  # For example only - please evaluate for your environment
  force_destroy = true

  tags = local.tags
}

#---------------------------------------------------------------
# MPI Operator for distributed training on Trainium
#---------------------------------------------------------------
data "http" "mpi_operator_yaml" {
  url = "https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.4.0/deploy/v2beta1/mpi-operator.yaml"
}

data "kubectl_file_documents" "mpi_operator_yaml" {
  content = data.http.mpi_operator_yaml.response_body
}

resource "kubectl_manifest" "mpi_operator" {
  for_each   = var.enable_mpi_operator ? data.kubectl_file_documents.mpi_operator_yaml.manifests : {}
  yaml_body  = each.value
  depends_on = [module.eks.eks_cluster_id]
}
