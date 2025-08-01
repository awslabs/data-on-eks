#-------------------------------------------
# For Rayhead High availability cluster
#-------------------------------------------
module "elasticache" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.2.0"

  cluster_id               = local.superset_name
  create_cluster           = true
  create_replication_group = false

  engine_version = "7.1"
  node_type      = "cache.r5.xlarge"

  apply_immediately = true
  multi_az_enabled = false

# Security Group
  vpc_id = local.vpc_id
  security_group_ids = [module.redis_security_group.security_group_id]

  # Subnet Group
  create_subnet_group = false
  subnet_group_name        = local.ec_subnet_group_name

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

  # pas disponible sur outpost
  log_delivery_configuration = []

  tags = local.tags

}


#---------------------------------------------------------------
# Redis security group
#---------------------------------------------------------------
module "redis_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.name
  description = "Complete Redis security group"
  vpc_id      = local.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      description = "Redis access from within VPC"
      cidr_blocks = local.private_subnets_cidr[0]
    },
  ]

  tags = local.tags
}
