---
title: Amazon MWAA
sidebar_position: 2
---

# Amazon Managed Workflows for Apache Airflow (MWAA)
Amazon Managed Workflows for Apache Airflow (MWAA) 是 Apache Airflow 的托管编排服务，使在云中大规模设置和操作端到端数据管道变得更加容易。Apache Airflow 是一个开源工具，用于以编程方式创作、调度和监控称为"工作流"的进程和任务序列。使用托管工作流，您可以使用 Airflow 和 Python 创建工作流，而无需管理可扩展性、可用性和安全性的底层基础设施。

该示例演示了如何使用 [Amazon Managed Workflows for Apache Airflow (MWAA)](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html) 以两种方式将作业分配给 Amazon EKS。
1. 直接创建作业并部署到 EKS。
2. 在 EMR 中将 EKS 注册为虚拟集群，并将 spark 作业分配给 EMR on EKS。

此示例的[代码存储库](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/managed-airflow-mwaa)。

### 考虑因素

理想情况下，我们建议将同步 requirements/sync dags 到 MWAA S3 存储桶的步骤添加为 CI/CD 管道的一部分。通常 Dags 开发与配置基础设施的 Terraform 代码有不同的生命周期。
为简单起见，我们提供了使用 Terraform 在 `null_resource` 上运行 AWS CLI 命令的步骤。

## 先决条件：

确保您已在本地安装以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 部署

要配置此示例：

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/schedulers/terraform/managed-airflow-mwaa
chmod +x install.sh
./install.sh
```

在命令提示符处输入区域以继续。

完成后，您将看到如下 terraform 输出。

![terraform output](../../../../../../docs/blueprints/job-schedulers/img/terraform-output.png)

在您的环境中配置了以下组件：
  - 示例 VPC、3 个私有子网和 3 个公有子网
  - 公有子网的互联网网关和私有子网的 NAT 网关
  - 带有一个托管节点组的 EKS 集群控制平面
  - EKS 托管附加组件：VPC_CNI、CoreDNS、Kube_Proxy、EBS_CSI_Driver
  - K8S 指标服务器和集群自动扩展器
