---
sidebar_position: 5
sidebar_label: Apache NiFi on EKS
---

# Apache NiFi on EKS

## 介绍

Apache NiFi 是一个开源数据集成和管理系统，旨在自动化和管理系统之间的数据流。它提供基于 Web 的用户界面，用于实时创建、监控和管理数据流。

凭借其强大而灵活的架构，Apache NiFi 可以处理广泛的数据源、云平台和格式，包括结构化和非结构化数据，并可用于各种数据集成场景，如数据摄取、数据处理（低到中等级别）、数据路由、数据转换和数据分发。

Apache NiFi 提供基于 GUI 的界面来构建和管理数据流，使非技术用户更容易使用。它还提供强大的安全功能，包括 SSL、SSH 和细粒度访问控制，以确保敏感数据的安全传输。无论您是数据分析师、数据工程师还是数据科学家，Apache NiFi 都为在 AWS 和其他平台上管理和集成数据提供了全面的解决方案。

:::caution

此蓝图应被视为实验性的，仅应用于概念验证。
:::

这个[示例](https://github.com/awslabs/data-on-eks/tree/main/streaming-platforms/nifi)部署了运行 Apache NiFi 集群的 EKS 集群。在示例中，Apache NiFi 在进行一些格式转换后将数据从 AWS Kinesis Data Stream 流式传输到 Amazon DynamoDB 表。

- 创建新的示例 VPC、3 个私有子网和 3 个公有子网
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关
- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的）和一个托管节点组
- 部署 Apache NiFi、AWS Load Balancer Controller、Cert Manager 和 External DNS（可选）附加组件
- 在 `nifi` 命名空间中部署 Apache NiFi 集群

## 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [jq](https://stedolan.github.io/jq/)

此外，对于 Ingress 的端到端配置，您需要提供以下内容：

1. 在您部署此示例的账户中配置的 [Route53 公共托管区域](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring.html)。例如 "example.com"
2. 在您部署此示例的账户 + 区域中的 [ACM 证书](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html)。首选通配符证书，例如 "*.example.com"

## 使用 Apache NiFi 部署 EKS 集群

### 克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

### 初始化 Terraform
