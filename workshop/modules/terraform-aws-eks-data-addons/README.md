# Terraform Module: Data & AI/ML Kubernetes Add-ons

This Terraform module contains commonly used Data & AI/ML related Kubernetes add-ons that are typically included in [Data on EKS](https://github.com/awslabs/data-on-eks) blueprints.
The purpose of this module is to provide customers with the flexibility to select and customize the add-ons they require while leveraging the Data on EKS blueprints.

## Important Note

Please be aware that this module is primarily intended for use with supported Data on EKS blueprints.
We kindly request that you refrain from adding new Kubernetes add-ons to this module unless they are directly related to [Data on EKS](https://github.com/awslabs/data-on-eks) blueprints.
Your understanding and cooperation are greatly appreciated. :pray:

## Available Add-ons

The following add-ons are included in this Terraform module:

| Add-on Name                                                                                                              | Description                                                     |
|--------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------|
| [EMR Spark Operator](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/spark-operator-gs.html)   | A Helm chart for EMR Spark Operator for EKS                   |
| [Apache Flink Operator](https://github.com/apache/flink-kubernetes-operator/tree/main/helm/flink-kubernetes-operator) | A Helm chart for Apache Flink Kubernetes Operator               |
| [Apache YuniKorn](https://github.com/apache/yunikorn-release/tree/master/helm-charts/yunikorn)                           | A Helm Chart for Apache YuniKorn Batch schdeuler for Kubernetes |
| [Spark History Server](https://github.com/Hyper-Mesh/spark-history-server)                       | A Helm Chart for Spark History Server for Kubernetes            |
| [JupyterHub](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/tree/main/jupyterhub)                       | A Helm Chart for zero-to-jupyterhub-k8s on Kubernetes          |
| [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator/tree/master/deployments/gpu-operator)                       | A Helm Chart for NVIDIA GPU Operator for Kubernetes            |
| [Spark Operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator/tree/master/charts/spark-operator-chart)   | A Helm chart for Spark on Kubernetes operator  

Other commonly used add-ons with Data on EKS Blueprints:

**NOTE**: Please be aware that some of these add-ons may be deprecated in favor of EKS Blueprints add-ons or EKS Managed add-ons.


| Add-on Name                                                   | Description                 |
|---------------------------------------------------------------|-----------------------------|
| [prometheus](https://prometheus-community.github.io/helm-charts) | A Helm Chart for Prometheus |
| [kubecost](oci://public.ecr.aws/kubecost)  | A Helm Chart for Kubecost   |
| [Grafana](https://grafana.github.io/helm-charts) | A Helm Chart for Grafana    |

Please refer to the documentation of each add-on for more details on usage and configuration.

----

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.72 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.4.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.72 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.4.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_grafana_irsa"></a> [grafana\_irsa](#module\_grafana\_irsa) | ./irsa | n/a |
| <a name="module_spark_history_server_irsa"></a> [spark\_history\_server\_irsa](#module\_spark\_history\_server\_irsa) | ./irsa | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_iam_policy.grafana](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [helm_release.airflow](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.emr_spark_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.flink_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.grafana](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.jupyterhub](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.kubecost](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.nvidia_gpu_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.prometheus](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.spark_history_server](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.spark_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.yunikorn](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_airflow_helm_config"></a> [airflow\_helm\_config](#input\_airflow\_helm\_config) | Airflow Helm Chart config | `any` | `{}` | no |
| <a name="input_emr_spark_operator_helm_config"></a> [emr\_spark\_operator\_helm\_config](#input\_emr\_spark\_operator\_helm\_config) | Helm configuration for Spark Operator with EMR Runtime | `any` | `{}` | no |
| <a name="input_enable_airflow"></a> [enable\_airflow](#input\_enable\_airflow) | Enable Airflow add-on | `bool` | `false` | no |
| <a name="input_enable_emr_spark_operator"></a> [enable\_emr\_spark\_operator](#input\_enable\_emr\_spark\_operator) | Enable the Spark Operator to submit jobs with EMR Runtime | `bool` | `false` | no |
| <a name="input_enable_flink_operator"></a> [enable\_flink\_operator](#input\_enable\_flink\_operator) | Enable Flink Operator add-on | `bool` | `false` | no |
| <a name="input_enable_grafana"></a> [enable\_grafana](#input\_enable\_grafana) | Enable Grafana add-on | `bool` | `false` | no |
| <a name="input_enable_jupyterhub"></a> [enable\_jupyterhub](#input\_enable\_jupyterhub) | Enable Jupyterhub Add-On | `bool` | `false` | no |
| <a name="input_enable_kubecost"></a> [enable\_kubecost](#input\_enable\_kubecost) | Enable Kubecost add-on | `bool` | `false` | no |
| <a name="input_enable_nvidia_gpu_operator"></a> [enable\_nvidia\_gpu\_operator](#input\_enable\_nvidia\_gpu\_operator) | Enable NVIDIA GPU Operator add-on | `bool` | `false` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Enable Community Prometheus add-on | `bool` | `false` | no |
| <a name="input_enable_spark_history_server"></a> [enable\_spark\_history\_server](#input\_enable\_spark\_history\_server) | Enable Spark History Server add-on | `bool` | `false` | no |
| <a name="input_enable_spark_operator"></a> [enable\_spark\_operator](#input\_enable\_spark\_operator) | Enable Spark on K8s Operator add-on | `bool` | `false` | no |
| <a name="input_enable_yunikorn"></a> [enable\_yunikorn](#input\_enable\_yunikorn) | Enable Apache YuniKorn K8s scheduler add-on | `bool` | `false` | no |
| <a name="input_flink_operator_helm_config"></a> [flink\_operator\_helm\_config](#input\_flink\_operator\_helm\_config) | Flink Operator Helm Chart config | `any` | `{}` | no |
| <a name="input_grafana_helm_config"></a> [grafana\_helm\_config](#input\_grafana\_helm\_config) | Grafana Helm Chart config | `any` | `{}` | no |
| <a name="input_jupyterhub_helm_config"></a> [jupyterhub\_helm\_config](#input\_jupyterhub\_helm\_config) | Helm configuration for JupyterHub | `any` | `{}` | no |
| <a name="input_kubecost_helm_config"></a> [kubecost\_helm\_config](#input\_kubecost\_helm\_config) | Kubecost Helm Chart config | `any` | `{}` | no |
| <a name="input_nvidia_gpu_operator_helm_config"></a> [nvidia\_gpu\_operator\_helm\_config](#input\_nvidia\_gpu\_operator\_helm\_config) | Helm configuration for NVIDIA GPU Operator | `any` | `{}` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | The ARN of the cluster OIDC Provider | `string` | n/a | yes |
| <a name="input_prometheus_helm_config"></a> [prometheus\_helm\_config](#input\_prometheus\_helm\_config) | Community Prometheus Helm Chart config | `any` | `{}` | no |
| <a name="input_spark_history_server_helm_config"></a> [spark\_history\_server\_helm\_config](#input\_spark\_history\_server\_helm\_config) | Helm configuration for Spark History Server | `any` | `{}` | no |
| <a name="input_spark_operator_helm_config"></a> [spark\_operator\_helm\_config](#input\_spark\_operator\_helm\_config) | Helm configuration for Spark K8s Operator | `any` | `{}` | no |
| <a name="input_yunikorn_helm_config"></a> [yunikorn\_helm\_config](#input\_yunikorn\_helm\_config) | Helm configuration for Apache YuniKorn | `any` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_jupyterhub"></a> [jupyterhub](#output\_jupyterhub) | jupyterhub Helm Chart metadata |
| <a name="output_kubecost"></a> [kubecost](#output\_kubecost) | Kubecost Helm Chart metadata |
| <a name="output_prometheus"></a> [prometheus](#output\_prometheus) | Prometheus Helm Chart metadata |
| <a name="output_spark_history_server"></a> [spark\_history\_server](#output\_spark\_history\_server) | Spark History Server Helm Chart metadata |
| <a name="output_spark_operator"></a> [spark\_operator](#output\_spark\_operator) | Spark Operator Helm Chart metadata |
| <a name="output_yunikorn"></a> [yunikorn](#output\_yunikorn) | Yunikorn Helm Chart metadata |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
