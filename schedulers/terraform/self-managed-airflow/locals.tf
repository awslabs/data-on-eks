#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region

  vpc_cidr                      = var.vpc_cidr
  azs                           = slice(data.aws_availability_zones.available.names, 0, 3)
  airflow_name                  = "airflow"
  airflow_service_account       = "airflow-webserver-sa"
  airflow_webserver_secret_name = "airflow-webserver-secret-key"
  efs_storage_class             = "efs-sc"
  efs_pvc                       = "airflowdags-pvc"
  vpc_endpoints                 = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
