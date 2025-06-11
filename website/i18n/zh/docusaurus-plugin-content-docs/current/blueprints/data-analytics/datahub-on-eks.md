---
sidebar_position: 6
sidebar_label: EKS上的DataHub
---
# EKS上的DataHub

## 介绍
DataHub是一个开源数据目录，支持端到端数据发现、数据可观测性和数据治理。这个广泛的元数据平台允许用户从各种来源收集、存储和探索元数据，如数据库、数据湖、流平台和ML特征存储。DataHub提供许多[功能](https://datahubproject.io/docs/features/)，用于搜索和浏览元数据的丰富UI，以及用于与其他应用程序集成的API。

这个[蓝图](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/datahub-on-eks)在EKS集群上部署DataHub，使用Amazon OpenSearch Service、Amazon Managed Streaming for Apache Kafka (Amazon MSK)和Amazon RDS for MySQL作为底层数据模型和索引的存储层。

## AWS上的DataHub

在AWS上，DataHub可以在EKS集群上运行。通过使用EKS，您可以利用Kubernetes的强大功能和灵活性来部署和扩展DataHub组件，并利用其他AWS服务和功能，如IAM、VPC和CloudWatch，来监控和保护DataHub集群。

DataHub还依赖于许多底层基础设施和服务才能运行，包括消息代理、搜索引擎、图形数据库和关系数据库，如MySQL或PostgreSQL。AWS提供了一系列托管和无服务器服务，可以满足DataHub的需求并简化其部署和操作。

1. DataHub可以使用Amazon Managed Streaming for Apache Kafka (MSK)作为元数据摄取和消费的消息层。MSK是一个完全托管的Apache Kafka服务，因此您不需要处理Kafka集群的配置、配置和维护。
2. DataHub将元数据存储在关系数据库和搜索引擎中。对于关系数据库，此蓝图使用Amazon RDS for MySQL，这也是一个托管服务，简化了MySQL数据库的设置和操作。RDS for MySQL还提供了DataHub存储元数据所需的高可用性、安全性和其他功能。
3. 对于搜索引擎，此蓝图使用Amazon OpenSearch服务为元数据提供快速且可扩展的搜索功能。
4. 此蓝图在EKS上为DataHub部署了一个Schema Registry服务。您也可以选择使用Glue Schema Registry (https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html)。对Glue Schema Registry的支持将包含在此蓝图的未来版本中。

![img.jpg](../../../../../../docs/blueprints/data-analytics/img/datahub-arch.jpg)

## 部署解决方案

此蓝图默认将EKS集群部署到新的VPC中：

- 创建一个新的示例VPC、2个私有子网和2个公共子网
- 为公共子网创建互联网网关，为私有子网创建NAT网关

您也可以通过将`create_vpc`变量的值设置为`false`并指定`vpc_id`、`private_subnet_ids`和`vpc_cidr`值来部署到现有VPC。

- 创建带有公共端点的EKS集群控制平面（仅用于演示原因），带有核心托管节点组、按需节点组和用于Spark工作负载的Spot节点组。
- 部署Metrics server、Cluster Autoscaler、Prometheus server和AMP workspace以及AWS LoadBalancer Controller。

然后为DataHub配置存储服务。

- 创建安全组，以及在部署EKS集群的每个私有子网/可用区中有一个数据节点的OpenSearch域。
- 为MSK创建安全组、kms密钥和配置。在每个私有子网中创建带有一个代理的MSK集群。
- 创建启用了多可用区的RDS MySQL数据库实例。

最后，它部署datahub-prerequisites和datahub helm图表，在EKS集群上设置datahub pod/服务。启用了Ingress（如datahub_values.yaml中配置的），AWS LoadBalancer Controller将配置一个ALB来暴露DataHub前端UI。

:::info
您可以通过更改`variables.tf`中的值来自定义蓝图，以部署到不同的区域（默认为`us-west-2`），使用不同的集群名称、子网/可用区数量，或禁用像fluentbit这样的附加组件
:::

:::info
如果您的账户中已经有opensearch服务，则OpenSearch的服务链接角色已经存在。您需要将变量`create_iam_service_linked_role_es`的默认值更改为`false`，以避免部署中出现错误。
:::

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

此外，您需要在账户中创建opensearch服务链接角色。要验证并在需要时创建角色，请运行：
```
aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com || true
```

# 如果角色已成功创建，您将看到：
# An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForOpenSearch has been taken in this account, please try a different suffix.

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行`install.sh`脚本

```bash
cd data-on-eks/analytics/terraform/datahub-on-eks
chmod +x install.sh
./install.sh
```

:::caution
`install.sh`脚本按顺序为每个模块运行`terraform apply -target`。模块依赖关系配置为在您只运行`terraform apply`时按正确顺序应用。但是，配置附加组件和MSK、OpenSearch和RDS实例通常需要超过15分钟，导致之后配置kubernetes和helm资源/模块时由于身份验证令牌过期而出错。因此，如果您使用`terraform apply`而不是运行`install.sh`，您可能需要多次运行它，terraform将每次使用新令牌恢复失败的资源，并最终完成部署。
:::


### 验证部署

部署完成后，我们可以访问DataHub UI并测试从示例数据源导入元数据。出于演示目的，此蓝图使用公共LoadBalancer（内部#私有Load Balancer只能在VPC内访问）为datahub FrontEnd UI创建Ingress对象。对于生产工作负载，您可以修改datahub_values.yaml以使用内部LB：

```
datahub-frontend:
  enabled: true
  image:
    repository: linkedin/datahub-frontend-react
  # Set up ingress to expose react front-end
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: **internal # 私有Load Balancer只能在VPC内访问**
      alb.ingress.kubernetes.io/target-type: instance
```

您可以从输出`frontend_url`中找到datahub前端的URL，或通过运行以下kubectl命令：

```sh
kubectl get ingress datahub-datahub-frontend -n datahub

# 输出应该如下所示
NAME                       CLASS    HOSTS   ADDRESS                                                                 PORTS   AGE
datahub-datahub-frontend   <none>   *       k8s-datahub-datahubd-xxxxxxxxxx-xxxxxxxxxx.<region>.elb.amazonaws.com   80      nn
```

从输出中复制ADDRESS字段，然后打开浏览器并输入URL为`http://<address>/`。在提示时输入`datahub`作为用户名和密码。我们可以像下面这样查看DataHub UI。

![img.png](../../../../../../docs/blueprints/data-analytics/img/datahub-ui.png)

## 测试

按照这个[博客](https://aws.amazon.com/blogs/big-data/part-2-deploy-datahub-using-aws-managed-services-and-ingest-metadata-from-aws-glue-and-amazon-redshift/)中的步骤，将来自AWS Glue Data Catalog和Amazon Redshift的元数据，以及业务术语表和数据谱系，填充到DataHub中。

## 清理

要清理您的环境，请运行`cleanup.sh`脚本

```bash
chmod +x cleanup.sh
./cleanup.sh
```
