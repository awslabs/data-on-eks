# Récupération du security group
data "aws_security_group" "default_vpc_sg" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

# Construction endpoint
# We build this here because it was shared between access point
resource "aws_s3outposts_endpoint" "this" {
  outpost_id        = data.aws_outposts_outpost.default.id 
  security_group_id = data.aws_security_group.default_vpc_sg.id
  subnet_id         = module.outpost_subnet.subnet_id[0]
}