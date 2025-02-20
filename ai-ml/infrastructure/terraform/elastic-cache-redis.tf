#-------------------------------------------
# For Rayhead High availability cluster
#-------------------------------------------
module "elasticache" {
  create  = var.enable_rayserve_ha_elastic_cache_redis
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.2.0"

  cluster_id               = local.name
  create_cluster           = true
  create_replication_group = false

  engine_version = "7.1"
  node_type      = "cache.t4g.small"

  apply_immediately = true

  # Security Group
  vpc_id = module.vpc.vpc_id
  security_group_rules = {
    ingress_vpc = {
      # Default type is `ingress`
      # Default port is based on the default engine port
      description = "VPC traffic"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }

    ingress_from_eks_worker_node_tcp = {
      description                  = "Ingress rule to allow TCP on port 6379 from EKS Ray Head Node"
      protocol                     = "tcp"
      from_port                    = 6379
      referenced_security_group_id = module.eks.node_security_group_id
      to_port                      = 6379
      type                         = "ingress"
    }
  }

  # Subnet Group
  subnet_group_name        = local.name
  subnet_group_description = "${title(local.name)} subnet group"
  subnet_ids               = module.vpc.private_subnets

  # Parameter Group
  create_parameter_group      = true
  parameter_group_name        = local.name
  parameter_group_family      = "redis7"
  parameter_group_description = "${title(local.name)} parameter group"
  parameters = [
    {
      name  = "latency-tracking"
      value = "yes"
    }
  ]

  tags = local.tags

}
