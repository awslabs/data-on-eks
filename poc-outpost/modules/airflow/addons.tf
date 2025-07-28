resource "random_password" "airflow_admin" {
  length  = 16
  special = true
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source = "aws-ia/eks-data-addons/aws"
  version = "1.33.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = local.oidc_provider_arn

  #---------------------------------------------------------------
  # Airflow Add-on
  #---------------------------------------------------------------
  enable_airflow = true
  airflow_helm_config = {
    namespace = try(local.airflow_namespace, local.airflow_namespace)
    version = "1.17.0"
    values = [
      templatefile("${path.module}/helm-values/airflow-values.yaml", {
        # Airflow Postgres RDS Config
        airflow_db_user = local.airflow_name
        airflow_db_pass = try(sensitive(aws_secretsmanager_secret_version.postgres.secret_string), "")
        airflow_db_name = try(module.db.db_instance_name, "")
        airflow_db_host = try(element(split(":", module.db.db_instance_endpoint), 0), "")
        #Service Accounts
        worker_service_account = try(kubernetes_service_account_v1.airflow_worker.metadata[0].name, local.airflow_workers_service_account)
        scheduler_service_account = try(kubernetes_service_account_v1.airflow_scheduler.metadata[0].name, local.airflow_scheduler_service_account)
        api_server_service_account = try(kubernetes_service_account_v1.airflow_webserver.metadata[0].name, local.airflow_api_server_service_account)
        dag_processor_service_account = try(kubernetes_service_account_v1.airflow_dag.metadata[0].name, local.airflow_dag_processor_service_account)
        # S3 bucket config
        s3_bucket_name = try(module.airflow_s3_bucket.s3_bucket_id, "")
        airflow_dag_path                  = "/opt/airflow/dags"
        webserver_secret_name = local.airflow_webserver_secret_name

        webserver_default_user_password = random_password.airflow_admin.result


      })
    ]
  }
}

#---------------------------------------------------------------
# Airflow Vitual Service qui remplace l'Ingress
#---------------------------------------------------------------

module "trino_virtual_service" {
  source = "../virtualService"

  cluster_issuer_name = var.cluster_issuer_name
  virtual_service_name = local.airflow_name
  dns_name = "${local.airflow_name}.${local.main_domain}"
  service_name = "airflow-api-server"
  service_port = 8080
  namespace = local.airflow_namespace

  tags = local.tags

}
