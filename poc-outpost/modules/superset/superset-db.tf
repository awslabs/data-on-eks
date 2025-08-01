#---------------------------------------------------------------
# Elasticache for Superset Metadata
#---------------------------------------------------------------
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 5.0"

  identifier = local.superset_name

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "17"
  family               = "postgres17" # DB parameter group
  major_engine_version = "17"         # DB option group
  instance_class       = "db.r5.xlarge"  #outpost redis dev instance

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name                = local.superset_name
  username               = local.superset_name
  create_random_password = false
  password               = sensitive(aws_secretsmanager_secret_version.postgres.secret_string)
  port                   = 5432

  multi_az               = false
  db_subnet_group_name   = local.db_subnet_group_name
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  # RDS on Outposts doesn't support Enhanced Monitoring
  performance_insights_enabled          = false
  create_monitoring_role                = false
  monitoring_interval                   = 0
  monitoring_role_name                  = null
  monitoring_role_use_name_prefix       = false
  monitoring_role_description           = null

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  tags = local.tags
}

#---------------------------------------------------------------
# Superset Postgres Metastore DB Master password
#---------------------------------------------------------------
resource "random_password" "postgres" {
  length  = 16
  special = false
}
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "postgres" {
  name                    = "postgres-${local.superset_name}-${local.name}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id     = aws_secretsmanager_secret.postgres.id
  secret_string = random_password.postgres.result
}

#---------------------------------------------------------------
# PostgreSQL RDS security group
#---------------------------------------------------------------
module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.name
  description = "Complete PostgreSQL security group"
  vpc_id      = local.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = local.private_subnets_cidr[0]
    },
  ]

  tags = local.tags
}