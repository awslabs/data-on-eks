data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = local.name
}


locals {
  outpost_name = var.outpost_name
  output_subnet_id = var.output_subnet_id
  name   = var.name
  region = var.region
  vpc_id = var.vpc_id
  private_subnets_cidr = var.private_subnets_cidr
  oidc_provider_arn    = var.oidc_provider_arn
  db_subnet_group_name = var.db_subnets_group_name
  cluster_issuer_name = var.cluster_issuer_name
  main_domain = var.main_domain

  #---------------------------------------------------------------
  # Local variables airflow
  #---------------------------------------------------------------
  airflow_name                      = "airflowalb4"
  airflow_namespace                 = "airflow"
  airflow_scheduler_service_account = "airflow-scheduler"
  airflow_api_server_service_account = "airflow-api-server"
  airflow_workers_service_account   = "airflow-worker"
  airflow_dag_processor_service_account       = "airflow-dag-processor"
  airflow_webserver_secret_name     = "airflow-webserver-secret-key"
  #---------------------------------------------------------------


  tags = var.tags
}

