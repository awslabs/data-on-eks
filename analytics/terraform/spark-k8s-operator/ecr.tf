resource "aws_ecr_repository" "spot_balancer" {
  name                 = "${local.name}-spot-balancer"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
