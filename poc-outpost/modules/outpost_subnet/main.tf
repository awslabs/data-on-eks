resource "aws_subnet" "outpost_private" {
  vpc_id            = var.vpc_id
  cidr_block        = var.cidr_block
  availability_zone = var.outpost_az
  outpost_arn       = var.outpost_arn

  tags = merge(
    var.tags,
    { Name = "${var.name_prefix}-private-outpost" }
  )
}

resource "aws_route_table" "outpost_private" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.natgw_id
  }

  tags = merge(
    var.tags,
    { Name = "${var.name_prefix}-private-outpost" }
  )
}

resource "aws_route_table_association" "outpost_private" {
  subnet_id      = aws_subnet.outpost_private.id
  route_table_id = aws_route_table.outpost_private.id
}
