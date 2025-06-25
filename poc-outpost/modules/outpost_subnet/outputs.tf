output "subnet_id" {
  description = "The ID of the Outpost private subnet"
  type        = list(string)
  value = [aws_subnet.outpost_private.id]
}

output "route_table_id" {
  value = aws_route_table.outpost_private.id
}
