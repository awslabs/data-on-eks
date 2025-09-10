---
sidebar_position: 2
sidebar_label: EMR on EKS with Karpenter
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# EMR on EKS with [Karpenter](https://karpenter.sh/)

## 介绍

在这个[模式](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter)中，您将部署一个 EMR on EKS 集群并使用 [Karpenter](https://karpenter.sh/) NodePool 来扩展 Spark 作业。

**架构**
![emr-eks-karpenter](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-karpenter.png)

此模式使用固定的默认值来保持部署体验简单，但也保持灵活性，以便您可以在部署期间选择必要的附加组件。如果您是 EMR on EKS 的新手，我们建议保持默认值，只有在有可行的替代选项时才进行自定义。

在基础设施方面，以下是此模式创建的资源

- 创建具有公共端点的 EKS 集群控制平面（推荐用于演示/概念验证环境）
- 一个托管节点组
  - 核心节点组，包含跨多个可用区的 3 个实例，用于运行系统关键 Pod。例如，Cluster Autoscaler、CoreDNS、可观察性、日志记录等。
- 启用 EMR on EKS
  - 为数据团队创建两个命名空间（`emr-data-team-a`、`emr-data-team-b`）
  - 为两个命名空间创建 Kubernetes 角色和角色绑定（`emr-containers` 用户）
  - 两个团队作业执行所需的 IAM 角色
  - 使用 `emr-containers` 用户和 `AWSServiceRoleForAmazonEMRContainers` 角色更新 `AWS_AUTH` 配置映射
  - 在作业执行角色和 EMR 托管服务账户的身份之间创建信任关系
