# Récupération du security group
# data "aws_security_group" "default_vpc_sg" {
#   name   = "default"
#   vpc_id = module.vpc.vpc_id
# }

# Construction endpoint
# We build this here because it was shared between access point
# resource "aws_s3outposts_endpoint" "this" {
#   outpost_id        = data.aws_outposts_outpost.default.id
#   security_group_id = data.aws_security_group.default_vpc_sg.id
#   subnet_id         = module.outpost_subnet.subnet_id[0]
# }

resource "aws_security_group" "outposts_sg" {
  name        = "poc-outposts-sg"
  description = "security group with all inbound and outbound traffic in outpost subnet"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "All inbound in outpost subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = local.private_subnets_cidr
  }

  egress {
    description = "All outbound in outpost subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = local.private_subnets_cidr
  }

  tags = {
    Name = local.name
  }
}

resource "aws_s3outposts_endpoint" "endpoint_s3_outpost" {
  outpost_id        = data.aws_outposts_outpost.default.id
  subnet_id         = module.outpost_subnet.subnet_id[0]
  security_group_id = aws_security_group.outposts_sg.id
}