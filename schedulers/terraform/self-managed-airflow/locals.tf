#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)
  
  airflow_name                          = "airflow"
  airflow_version                       = "2.5.3"
  airflow_namespace                     = "airflow"
  airflow_scheduler_service_account      = "airflow-scheduler"
  airflow_webserver_service_account      = "airflow-webserver"
  airflow_workers_service_account        = "airflow-worker"
  airflow_webserver_secret_name          = "airflow-webserver-secret-key"
  efs_storage_class                     = "efs-sc"
  efs_pvc                               = "airflowdags-pvc"
  vpc_endpoints                         = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]
  # This role will be created
  karpenter_iam_role_name = format("%s-%s", "karpenter", local.name)
  
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}