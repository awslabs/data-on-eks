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
    # INFO: fsx node daemonset wont be placed on Karpenter nodes with taints without the following toleration
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
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
        storage_class_type  = kubernetes_storage_class.default_gp3.id
      }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {})
    ]
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.2" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_neuron_device_plugin  = true
  enable_aws_efa_k8s_device_plugin = true
  #---------------------------------------
  # Volcano Scheduler for TorchX
  #---------------------------------------
  enable_volcano = true
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
# Create Volcano Queue once the Volcano add-on is installed
#---------------------------------------------------------------
resource "kubectl_manifest" "volcano_queue" {
  yaml_body = <<YAML
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: test
spec:
  weight: 1
  reclaimable: false
  capability:
    cpu: 2
YAML

  depends_on = [module.eks_data_addons]
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
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

locals {
  karpenter_trn1_32xl_lt_name = format("%s-trn132xl-lt", local.name)
}

#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/karpenter-provisioners/trainium-*.yaml"
  vars = {
    azs                  = local.region
    eks_cluster_id       = local.name
    launch_template_name = local.karpenter_trn1_32xl_lt_name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
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
# Create a Launch Template Userdata for Trainium
#---------------------------------------------------------------
data "cloudinit_config" "trn1_lt" {
  base64_encode = true
  gzip          = false
  boundary      = "//"

  # Prepend to existing user data supplied by AWS EKS
  part {
    content_type = "text/x-shellscript"
    content      = <<-EOT
      cat <<-EOF > /etc/profile.d/bootstrap.sh
      #!/bin/sh

      # Configure NVMe volumes in RAID0 configuration
      # https://github.com/awslabs/amazon-eks-ami/blob/056e31f8c7477e893424abce468cb32bbcd1f079/files/bootstrap.sh#L35C121-L35C126
      # Mount will be: /mnt/k8s-disks
      export LOCAL_DISKS='raid0'

      # Install Neuron monitoring tools
      yum install aws-neuronx-tools-2.* -y
      export PATH=/opt/aws/neuron/bin:$PATH

      # EFA Setup for Trainium and Inferentia
      export FI_EFA_USE_DEVICE_RDMA=1
      export FI_PROVIDER=efa
      export FI_EFA_FORK_SAFE=1

      curl -O https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz
      tar -xf aws-efa-installer-latest.tar.gz && cd aws-efa-installer
      ./efa_installer.sh -y -g
      /opt/amazon/efa/bin/fi_info -p efa
      EOF

      # Source extra environment variables in bootstrap script
      sed -i '/^set -o errexit/a\\nsource /etc/profile.d/bootstrap.sh' /etc/eks/bootstrap.sh

      # Bootstrap the node
      B64_CLUSTER_CA=${module.eks.cluster_certificate_authority_data}
      API_SERVER_URL=${module.eks.cluster_endpoint}
      /etc/eks/bootstrap.sh ${local.name} --kubelet-extra-args "--node-labels=eks.amazonaws.com/nodegroup-image=${data.aws_ami.eks_gpu.id}" --b64-cluster-ca $B64_CLUSTER_CA --apiserver-endpoint $API_SERVER_URL

    EOT
  }
}

#---------------------------------------------------------------
# This Terraform code defines a data block to fetch the most recent Amazon Machine Image (AMI)
# for an Amazon Elastic Kubernetes Service (EKS) cluster with GPU support.
#---------------------------------------------------------------
data "aws_ami" "eks_gpu" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-gpu-node-${var.eks_cluster_version}-*"]
  }
}

#---------------------------------------------------------------
# AWS Launch Template Configuration for Karpenter Trn1.32xlarge Instances
#---------------------------------------------------------------
resource "aws_launch_template" "trn1_lt" {
  name        = local.karpenter_trn1_32xl_lt_name
  description = "Karpenter Trn1.32xlarge Launch Template"

  user_data = data.cloudinit_config.trn1_lt.rendered

  ebs_optimized = true

  image_id = data.aws_ami.eks_gpu.id

  iam_instance_profile {
    name = module.eks_blueprints_addons.karpenter.node_instance_profile_name
  }

  # Commented for visiblity to implement this feature in the future
  #  placement {
  #   tenancy = "default"
  #   availability_zone = "${local.region}d"
  #   group_name        = local.karpenter_trn1_32xl_lt_name
  # }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 100
      delete_on_termination = true
      volume_type           = "gp3"
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      "karpenter.sh/discovery" = local.name
    })
  }

  # First network interface with device_index=0 and network_card_index=0
  network_interfaces {
    device_index                = 0
    network_card_index          = 0
    associate_public_ip_address = false
    interface_type              = "efa"
    delete_on_termination       = true
    security_groups             = [module.eks.node_security_group_id]
    description                 = "Karpenter EFA config for Trainium"
  }

  # Additional network interfaces with device_index=1 and network_card_index ranging from 1 to 7
  dynamic "network_interfaces" {
    for_each = range(1, 8) # Create 7 additional network interfaces
    content {
      device_index                = 1
      network_card_index          = network_interfaces.value
      associate_public_ip_address = false
      interface_type              = "efa"
      delete_on_termination       = true
      security_groups             = [module.eks.node_security_group_id]
      description                 = "Karpenter EFA config for Trainium"
    }
  }
}
