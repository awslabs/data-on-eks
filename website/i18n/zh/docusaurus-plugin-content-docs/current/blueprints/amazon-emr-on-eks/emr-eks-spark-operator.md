---
sidebar_position: 3
sidebar_label: EMR Runtime with Spark Operator
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# EMR Runtime with Spark Operator

## 介绍
在这篇文章中，我们将学习如何部署带有 EMR Spark Operator 的 EKS 并使用 EMR 运行时执行示例 Spark 作业。

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter)中，您将配置使用 Spark Operator 和 EMR 运行时运行 Spark 应用程序所需的以下资源。

- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的）
- 两个托管节点组
  - 核心节点组，包含 3 个可用区，用于运行系统关键 Pod。例如，Cluster Autoscaler、CoreDNS、可观察性、日志记录等。
  - Spark 节点组，包含单个可用区，用于运行 Spark 作业
- 创建一个数据团队（`emr-data-team-a`）
  - 为团队创建新的命名空间
  - 为团队执行角色创建新的 IAM 角色
- `emr-data-team-a` 的 IAM 策略
- Spark History Server Live UI 配置为通过 NLB 和 NGINX 入口控制器监控正在运行的 Spark 作业
- 部署以下 Kubernetes 附加组件
    - 托管附加组件
        - VPC CNI、CoreDNS、KubeProxy、AWS EBS CSI Driver
    - 自管理附加组件
        - 具有 HA 的 Metrics server、CoreDNS 集群比例自动扩展器、Cluster Autoscaler、Prometheus Server 和 Node Exporter、AWS for FluentBit、EKS 的 CloudWatchMetrics

<CollapsibleContent header={<h2><span>EMR Spark Operator</span></h2>}>

</CollapsibleContent>
