#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region

  vpc_cidr                      = var.vpc_cidr
  azs                           = slice(data.aws_availability_zones.available.names, 0, 3)
  strimzi_kafka_name             = "strimzi-kafka-operator"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

  csi_name = "aws-ebs-csi-driver"

  csi_create_irsa = true
  csi_namespace   = "kube-system"

}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.15.0"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Recommended outbound traffic for Node groups
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  managed_node_groups = {
    # Core node group for deploying all the critical add-ons
    mng1 = {
      node_group_name = "core-node-grp"
      subnet_ids      = module.vpc.private_subnets

      instance_types = ["m5.xlarge"]
      ami_type       = "AL2_x86_64"
      capacity_type  = "ON_DEMAND"

      disk_size = 100
      disk_type = "gp3"

      max_size               = 9
      min_size               = 3
      desired_size           = 3
      create_launch_template = true
      launch_template_os     = "amazonlinux2eks"

      update_config = [{
        max_unavailable_percentage = 50
      }]

      k8s_labels = {
        Environment   = "preprod"
        Zone          = "test"
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      # See this doc node-template tags https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-can-i-scale-a-node-group-to-0
      additional_tags = {
        Name                                                             = "core-node-grp"
        subnet_type                                                      = "private"
        "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
        "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
        "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "core"
        "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
        "k8s.io/cluster-autoscaler/${local.name}"                        = "owned"
        "k8s.io/cluster-autoscaler/enabled"                              = "true"
      }
    }
    # Kafka workload node group for deploying Kafka Brokers
    mng2 = {
      node_group_name = "kafka-node-grp"
      subnet_ids      = module.vpc.private_subnets

      instance_types = ["r6i.2xlarge"]
#      Im4gn.4xlarge , m5.8xlarge, r6i.2xlarge, Check for best instance
      ami_type       = "AL2_x86_64"
      capacity_type  = "ON_DEMAND"

      disk_size = 100
      disk_type = "gp3"

      max_size               = 12 # According to workload
      min_size               = 3
      desired_size           = 3
      create_launch_template = true
      launch_template_os     = "amazonlinux2eks"

      update_config = [{
        max_unavailable_percentage = 50
      }]

      k8s_labels = {
        Environment   = "preprod"
        Zone          = "test"
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "kafka"
      }

      k8s_taints = [{ key = "dedicated", value = "kafka", effect = "NO_SCHEDULE" }]

      # See this doc node-template tags https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-can-i-scale-a-node-group-to-0
      additional_tags = {
        Name                                                             = "kafka-node-grp"
        subnet_type                                                      = "private"
        "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
        "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
        "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "kafka"
        "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
        "k8s.io/cluster-autoscaler/${local.name}"                        = "owned"
        "k8s.io/cluster-autoscaler/enabled"                              = "true"
      }
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# GP3 Storage Class
#---------------------------------------------------------------
resource "kubectl_manifest" "gp3_sc" {
  yaml_body = <<-YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
  name: gp3
parameters:
  fsType: xfs
  type: gp3
  encrypted: "true"
allowVolumeExpansion: true
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
YAML

  depends_on = [module.eks_blueprints.eks_cluster_id]
}