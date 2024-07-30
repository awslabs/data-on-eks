locals {
  name   = var.name
  region = var.region
  //azs    = slice(data.aws_availability_zones.available.names, 0, 3)
  s3_express_supported_az_ids = [
    "use1-az4", "use1-az5", "use1-az6", "usw2-az1", "usw2-az3", "usw2-az4", "apne1-az1", "apne1-az4", "eun1-az1", "eun1-az2", "eun1-az3"
  ]

  az_ids = [
    for az_id in data.aws_availability_zones.available.zone_ids :
    az_id if contains(local.s3_express_supported_az_ids, az_id)
  ]

  azs = [for zone_id in local.az_ids : [
    for az in data.aws_availability_zones.available.zone_ids :
    data.aws_availability_zones.available.names[index(data.aws_availability_zones.available.zone_ids, az)] if az == zone_id
  ][0]]

  s3_express_zone_id   = local.az_ids[0]
  s3_express_zone_name = local.azs[0]

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Environment = "${local.name}"
  }
}