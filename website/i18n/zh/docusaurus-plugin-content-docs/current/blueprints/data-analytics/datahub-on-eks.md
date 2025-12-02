---
sidebar_position: 6
sidebar_label: DataHub on EKS
---
# EKS 上的 DataHub

## 介绍
DataHub 是一个开源数据目录，支持端到端的数据发现、数据可观测性和数据治理。这个广泛的元数据平台允许用户从各种来源收集、存储和探索元数据，例如数据库、数据湖、流平台和机器学习特征存储。DataHub 提供许多[功能](https://datahubproject.io/docs/features/)，包括用于搜索和浏览元数据的丰富 UI，以及用于与其他应用程序集成的 API。

这个[蓝图](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/datahub-on-eks)在 EKS 集群上部署 DataHub，使用 Amazon OpenSearch Service、Amazon Managed Streaming for Apache Kafka (Amazon MSK) 和 Amazon RDS for MySQL 作为底层数据模型和索引的存储层。

## AWS 上的 DataHub

在 AWS 上，DataHub 可以在 EKS 集群上运行。通过使用 EKS，您可以利用 Kubernetes 的强大功能和灵活性来部署和扩展 DataHub 组件，并利用其他 AWS 服务和功能，如 IAM、VPC 和 CloudWatch，来监控和保护 DataHub 集群。

DataHub 还依赖许多底层基础设施和服务来运行，包括消息代理、搜索引擎、图数据库和关系数据库（如 MySQL 或 PostgreSQL）。AWS 提供一系列托管和无服务器服务，可以满足 DataHub 的需求并简化其部署和操作。

1. DataHub 可以使用 Amazon Managed Streaming for Apache Kafka (MSK) 作为元数据摄取和消费的消息层。MSK 是一个完全托管的 Apache Kafka 服务，因此您无需处理 Kafka 集群的配置、配置和维护。
2. DataHub 将元数据存储在关系数据库和搜索引擎中。对于关系数据库，此蓝图使用 Amazon RDS for MySQL，这也是一个托管服务，简化了 MySQL 数据库的设置和操作。RDS for MySQL 还提供 DataHub 存储元数据所需的高可用性、安全性和其他功能。
3. 对于搜索引擎，此蓝图使用 Amazon OpenSearch 服务为元数据提供快速且可扩展的搜索功能。
4. 此蓝图在 EKS 上为 DataHub 部署 Schema Registry 服务。您也可以选择使用 Glue Schema Registry (https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html)。对 Glue Schema Registry 的支持将包含在此蓝图的未来版本中。

![img.jpg](../../../../../../docs/blueprints/data-analytics/img/datahub-arch.jpg)

## 部署解决方案

此蓝图默认将 EKS 集群部署到新的 VPC 中：

- 创建新的示例 VPC、2 个私有子网和 2 个公有子网
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关

您也可以通过将 `create_vpc` 变量的值设置为 `false` 并指定 `vpc_id`、`private_subnet_ids` 和 `vpc_cidr` 值来部署到现有 VPC。

- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的），包含核心托管节点组、按需节点组和用于 Spark 工作负载的 Spot 节点组。
- 部署 Metrics server、Cluster Autoscaler、Prometheus server 和 AMP 工作空间，以及 AWS LoadBalancer Controller。

然后为 DataHub 配置存储服务。

- 创建安全组，以及在 EKS 集群部署的每个私有子网/可用区中具有一个数据节点的 OpenSearch 域。
- 创建安全组、kms 密钥和 MSK 配置。在每个私有子网中创建具有一个代理的 MSK 集群。
- 创建启用多可用区的 RDS MySQL 数据库实例。

最后，它部署 datahub-prerequisites 和 datahub helm charts 以在 EKS 集群上设置 datahub pod/服务。启用 Ingress（如 datahub_values.yaml 中配置），AWS LoadBalancer Controller 将配置 ALB 以暴露 DataHub 前端 UI。

:::info
您可以通过更改 `variables.tf` 中的值来自定义蓝图，以部署到不同的区域（默认为 `us-west-2`），使用不同的集群名称、子网/可用区数量，或禁用 fluentbit 等插件
:::

:::info
如果您的账户中已经有 opensearch 服务，则 OpenSearch 的服务链接角色已经存在。您需要将变量 `create_iam_service_linked_role_es` 的默认值更改为 `false` 以避免部署错误。
:::

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

此外，您需要在账户中创建 opensearch 服务链接角色。要验证并在需要时创建角色，请运行：
```
aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com || true
```

# 如果角色已成功创建，您将看到：
# An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForOpenSearch has been taken in this account, please try a different suffix.

### 部署

克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行 `install.sh` 脚本

```bash
cd data-on-eks/analytics/terraform/datahub-on-eks
chmod +x install.sh
./install.sh
```

:::caution
`install.sh` 脚本按顺序为每个模块运行 `terraform apply -target`。模块依赖关系已配置，因此当您只运行 `terraform apply` 时，它们将按正确的顺序应用。但是，配置插件以及 MSK、OpenSearch 和 RDS 实例通常需要超过 15 分钟，由于身份验证令牌过期，会导致之后配置 kubernetes 和 helm 资源/模块时出错。因此，如果您使用 `terraform apply` 而不是运行 `install.sh`，您可能需要多次运行它，terraform 将使用新令牌恢复失败的资源，并最终完成部署。
:::

### 验证部署

部署完成后，我们可以访问 DataHub UI 并测试从示例数据源导入元数据。此蓝图为 datahub 前端 UI 创建 Ingress 对象，使用内部 LoadBalancer（只能在 VPC 内访问）。您可以从输出 `frontend_url` 中找到 datahub 前端的 URL，或通过运行以下 kubectl 命令：

```sh
kubectl get ingress datahub-datahub-frontend -n datahub

# 输出应如下所示
NAME                       CLASS    HOSTS   ADDRESS                                                                 PORTS   AGE
datahub-datahub-frontend   <none>   *       k8s-datahub-datahubd-xxxxxxxxxx-xxxxxxxxxx.<region>.elb.amazonaws.com   80      nn
```

从输出中复制 ADDRESS 字段，然后打开浏览器并输入 URL 为 `http://<address>/`。提示时输入 `datahub` 作为用户名。默认密码通过 Kubernetes secret 设置，您可以使用以下命令显示它：

```
kubectl get secret datahub-user-secret -n datahub -o jsonpath='{.data.*}' | base64 -d
```

登录后，我们将获得如下所示的 DataHub UI。

![img.png](../../../../../../docs/blueprints/data-analytics/img/datahub-ui.png)

## 测试

按照此[博客](https://aws.amazon.com/blogs/big-data/part-2-deploy-datahub-using-aws-managed-services-and-ingest-metadata-from-aws-glue-and-amazon-redshift/)中的步骤，将来自 AWS Glue Data Catalog 和 Amazon Redshift 的元数据，以及业务词汇表和数据血缘，填充到 DataHub 中。

## 清理

要清理您的环境，请运行 `cleanup.sh` 脚本。

```bash
chmod +x cleanup.sh
./cleanup.sh
```
