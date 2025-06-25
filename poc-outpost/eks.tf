# EKS Cluster using terraform-aws-modules/eks/aws
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = local.cluster_version
 
  # Avoid below option in production. It's just for POC purpose and to easier testing
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
 
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }
 
  vpc_id     = module.vpc.vpc_id
  control_plane_subnet_ids = module.vpc.public_subnets
  subnet_ids = module.outpost_subnet.subnet_id
 
  self_managed_node_groups = {
    outposts-ng = {
      name          = "outposts-ng"
      instance_type = "c5.2xlarge"
 
      min_size     = 2
      max_size     = 5
      desired_size = 2
 
      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=eks.amazonaws.com/compute-type=ec2'"
 
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp2"
            delete_on_termination = true
          }
        }
      }
 
      subnet_ids = module.outpost_subnet.subnet_id
    }
  }
 
  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true
 
  tags = local.tags

  depends_on = [module.vpc]
}