locals {

  azs = slice(data.aws_availability_zones.available.names, 0, var.num_azs)

  tags = merge(var.tags, {
    Blueprint = var.eks_cluster_name
  })
}
