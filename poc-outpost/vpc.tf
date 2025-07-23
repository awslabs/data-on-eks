#---------------------------------------------------------------
# Supporting Network Resources
#---------------------------------------------------------------
# WARNING: This VPC module includes the creation of an Internet Gateway and NAT Gateway, which simplifies cluster deployment and testing, primarily intended for sandbox accounts.
# IMPORTANT: For preprod and prod use cases, it is crucial to consult with your security team and AWS architects to design a private infrastructure solution that aligns with your security requirements

# We create 2 public subnets that host NAT and IGW and one private outpost subnet
# Configuration base on this example : https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/v6.0.1/examples/outpost/main.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  azs = local.azs

  # Public subnets: seulement pour les non-Outpost AZs (10.0.1.0/24, 10.0.2.0/24)
  public_subnets  = local.public_subnets_cidr
  private_subnets = local.factice_private_subnets_cidr # Subnet factice pour activer les routes NAT (si liste vide, le bind n'est pas fait par le module)

  private_subnet_tags = {
    "fake" = "true"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"              = 1,
    "kubernetes.io/cluster/${local.name}" = "owned",
  }

  # LIMITATION ACTUELLE DU MODULE VPC.
  # Le module active directement les COIP (Pool IP dans Outpost) si outpost_arn est setté. 
  # Mais l'outpost du POC est "No CoIP pools available with direct VPC routing 
  #      This local gateway route table uses direct VPC routing mode. Direct VPC routing and CoIP are mutually exclusive modes. 
  #      To switch between modes, you must create a new local gateway route table."
  # On crée donc le subnet privé en dehors de ce module officiel AWS
  # (Information issue de la console dans LGW Route Tables de l'outpost)

  # # Private subnet: seulement pour l'Outpost AZ (10.0.0.0/24)
  # private_subnets = local.private_subnets_cidr
  #   # Outpost is using single AZ specified in `outpost_az`
  # outpost_subnets = local.private_subnets_cidr
  # outpost_arn     = data.aws_outposts_outpost.default.arn
  # outpost_az      = local.outpost_az


  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}

module "outpost_subnet" {
  source = "./modules/outpost_subnet"

  vpc_id      = module.vpc.vpc_id
  natgw_id    = module.vpc.natgw_ids[0]
  cidr_block  = local.private_subnets_cidr[0]
  outpost_arn = data.aws_outposts_outpost.default.arn
  outpost_az  = data.aws_outposts_outpost.default.availability_zone
  name_prefix = local.name
  tags        = local.tags

  depends_on = [module.vpc]
}

#---------------------------------------------------------------
# using existing private subnets for creating db subnet on outpost RDS
#---------------------------------------------------------------
resource "aws_db_subnet_group" "private" {
  name       = "db-private-subnet-outpost-otl4"
  subnet_ids = module.outpost_subnet.subnet_id
  tags       = local.tags
}