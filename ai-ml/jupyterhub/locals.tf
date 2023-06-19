locals {
  name   = var.name
  region = var.region
  cog_domain_name    = var.cognito_domain
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
  
    # This role will be created 
  karpenter_iam_role_name = format("%s-%s", "karpenter", local.name)
}
