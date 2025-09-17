---
sidebar_label: VPC 配置
---

# 数据网络

## VPC 和 IP 考虑事项

### 默认 VPC CNI 配置
使用默认 VPC CNI 配置时，较大的节点将消耗更多 IP 地址。例如，运行 10 个 Pod 的 [`m5.8xlarge` 节点](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)将总共持有 60 个 IP（以满足 `WARM_ENI_TARGET=1`）。然而，`m5.16xlarge` 节点将持有 100 个 IP。

AWS VPC CNI 在 EKS worker 节点上维护这个 IP 地址的"热池"以分配给 Pod。当您的 Pod 需要更多 IP 地址时，CNI 必须与 EC2 API 通信以将地址分配给您的节点。

### 在您的 EKS 集群中规划大量 IP 地址使用。

在高流失或大规模扩展期间，这些 EC2 API 调用可能会受到速率限制，这将延迟 Pod 的配置，从而延迟工作负载的执行。此外，配置 VPC CNI 以最小化此热池可能会增加来自节点的 EC2 API 调用并增加速率限制的风险。

### 如果您的 IP 空间受限，请考虑使用辅助 CIDR。

如果您正在使用跨越多个连接的 VPC 或站点的网络，可路由地址空间可能有限。
例如，您的 VPC 可能限制为如下所示的小子网。在此 VPC 中，如果不调整 CNI 配置，我们将无法运行超过一个 `m5.16xlarge` 节点。

![初始 VPC](../../../../../../docs/bestpractices/networking/init-vpc.png)

您可以从不跨 VPC 路由的范围（例如 RFC 6598 范围，`100.64.0.0/10`）添加额外的 VPC CIDR。在这种情况下，我们向 VPC 添加了 `100.64.0.0/16`、`100.65.0.0/16` 和 `100.66.0.0/16`（因为这是最大 CIDR 大小），然后使用这些 CIDR 创建了新子网。
最后，我们在新子网中重新创建了节点组，保留现有的 EKS 集群控制平面。

![扩展的 VPC](../../../../../../docs/bestpractices/networking/expanded-vpc.png)

使用此配置，您仍然可以从连接的 VPC 与 EKS 集群控制平面通信，但您的节点和 Pod 有足够的 IP 地址来容纳您的工作负载和热池。

## 调优 VPC CNI

### VPC CNI 和 EC2 速率限制

当启动 EKS worker 节点时，它最初有一个单独的 ENI，附加了一个单独的 IP 地址供 EC2 实例通信。当 VPC CNI 启动时，它尝试配置可以分配给 Kubernetes Pod 的 IP 地址热池（[EKS 最佳实践指南中的更多详细信息](https://aws.github.io/aws-eks-best-practices/networking/vpc-cni/#overview)）。

VPC CNI 必须进行 AWS EC2 API 调用（如 `AssignPrivateIpV4Address` 和 `DescribeNetworkInterfaces`）以将这些额外的 IP 和 ENI 分配给 worker 节点。当 EKS 集群扩展节点或 Pod 的数量时，这些 EC2 API 调用的数量可能会激增。这种调用激增可能会遇到来自 EC2 API 的速率限制，以帮助服务的性能，并确保所有 Amazon EC2 客户的公平使用。这种速率限制可能导致 IP 地址池耗尽，而 CNI 试图分配更多 IP。

这些失败将导致如下错误，表明容器网络命名空间的配置失败，因为 VPC CNI 无法配置 IP 地址。

```
Failed to create pod sandbox: rpc error: code = Unknown desc = failed to set up sandbox container "xxxxxxxxxxxxxxxxxxxxxx" network for pod "test-pod": networkPlugin cni failed to set up pod test-pod_default" network: add cmd: failed to assign an IP address to container
```

此失败延迟了 Pod 的启动，并对 kubelet 和 worker 节点增加了压力，因为此操作会重试直到分配 IP 地址。为了避免此延迟，您可以配置 CNI 以减少所需的 EC2 API 调用数量。

### 在大型集群或具有大量流失的集群中避免使用 `WARM_IP_TARGET`

`WARM_IP_TARGET` 可以帮助限制小型集群或 Pod 流失非常低的集群的"浪费"IP。但是，VPC CNI 上的此环境变量需要在大型集群中仔细配置，因为它可能会增加 ipamd 的 IP 附加和分离操作的 EC2 API 调用数量，增加速率限制的风险和影响。
（`ipamd` 代表 IP 地址管理守护程序，[是 VPC CNI 的核心组件](https://docs.aws.amazon.com/eks/latest/best-practices/networking.html#amazon-virtual-private-cloud-vpc-cni)。它维护可用 IP 的热池以实现快速 Pod 启动时间。）

对于具有大量 Pod 流失的集群，建议将 `MINIMUM_IP_TARGET` 设置为略高于您计划在每个节点上运行的预期 Pod 数量的值。这将允许 CNI 在单个（或少数）调用中配置所有这些 IP 地址。

```hcl
  [...]

  # EKS 插件
  cluster_addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          MINIMUM_IP_TARGET        = "30"
        }
      })
    }
  }

  [...]
```
有关调整 VPC CNI 变量的详细信息，请参考 [github 上的此文档](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/eni-and-ip-target.md)。

### 使用 `MAX_ENI` 和 `max-pods` 限制大型实例类型上每个节点的 IP 数量

当使用较大的实例类型（如 `16xlarge` 或 `24xlarge`）时，[每个 ENI 可以分配的 IP 地址数量](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)可能相当大。例如，具有默认 CNI 配置 `WARM_ENI_TARGET=1` 的 `c5.18xlarge` 实例类型在运行少量 Pod 时最终会持有 100 个 IP 地址（每个 ENI 50 个 IP * 2 个 ENI）。

对于某些工作负载，CPU、内存或其他资源将限制该 `c5.18xlarge` 上的 Pod 数量，然后我们需要超过 50 个 IP。在这种情况下，您可能希望能够在该实例上最多运行 30-40 个 Pod。

```hcl
  [...]

  # EKS 插件
  cluster_addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          MAX_ENI           = "1"
        }
      })
    }
  }

  [...]
```

在 CNI 上设置 `MAX_ENI=1` 选项，这将限制每个节点能够配置的 IP 地址数量，但它不会限制 kubernetes 尝试调度到节点的 Pod 数量。这可能导致 Pod 被调度到无法配置更多 IP 地址的节点的情况。

要限制 IP *并且*阻止 k8s 调度太多 Pod，您需要：

1. 更新 CNI 配置环境变量以设置 `MAX_ENI=1`
2. 更新 worker 节点上 kubelet 的 `--max-pods` 选项。

要配置 --max-pods 选项，您可以更新 worker 节点的用户数据，[通过 bootstrap.sh 脚本中的 --kubelet-extra-args 设置此选项](https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh)。默认情况下，此脚本为 kubelet 配置 max-pods 值，`--use-max-pods false` 选项在提供您自己的值时禁用此行为：

```hcl
  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.xlarge"]

      min_size     = 0
      max_size     = 5
      desired_size = 3

      pre_bootstrap_user_data = <<-EOT

      EOT

      bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=<your_value>'"

    }
```

一个问题是每个 ENI 的 IP 数量根据实例类型而不同（[例如 `m5d.2xlarge` 每个 ENI 可以有 15 个 IP，而 `m5d.4xlarge` 每个 ENI 可以持有 30 个 IP](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)）。这意味着硬编码 `max-pods` 的值可能会在您更改实例类型或在混合实例环境中造成问题。

在 EKS 优化 AMI 版本中，[包含一个脚本，可用于帮助计算 AWS 推荐的 max-pods 值](https://github.com/awslabs/amazon-eks-ami/blob/master/files/max-pods-calculator.sh)。如果您想为混合实例自动化此计算，您还需要更新实例的用户数据以使用 `--instance-type-from-imds` 标志从实例元数据自动发现实例类型。

```hcl
  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.xlarge"]

      min_size     = 0
      max_size     = 5
      desired_size = 3

      pre_bootstrap_user_data = <<-EOT
        /etc/eks/max-pod-calc.sh --instance-type-from-imds —cni-version 1.13.4 —cni-max-eni 1
      EOT

      bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=<your_value>'"

    }
```

#### 使用 Karpenter 的 Maxpods

默认情况下，Karpenter 配置的节点将[基于节点实例类型](https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt)在节点上具有最大 Pod 数。要如上所述配置 `--max-pods` 选项，可以通过在 `.spec.kubeletConfiguration` 中指定 `maxPods` 在 Provisioner 级别定义。此值将在 Karpenter Pod 调度期间使用，并在 kubelet 启动时传递给 `--max-pods`。

以下是示例 Provisioner 规范：

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  providerRef:
    name: default
  requirements:
    - key: "karpenter.k8s.aws/instance-category"
      operator: In
      values: ["c", "m", "r"]
    - key: "karpenter.sh/capacity-type" # 如果不包含，AWS 云提供商的 webhook 将默认为按需
      operator: In
      values: ["spot", "on-demand"]

  # Karpenter 提供指定一些额外 Kubelet 参数的能力。
  # 这些都是可选的，为额外的自定义和用例提供支持。
  kubeletConfiguration:
    maxPods: 30
```

## 应用程序

### 扩展 CoreDNS
#### 默认行为
Route 53 Resolver 对每个 EC2 实例的每个网络接口强制执行每秒 1024 个数据包的限制，此限制不可调整。在 EKS 集群中，CoreDNS 默认运行两个副本，每个副本在单独的 EC2 实例上。当 DNS 流量超过 CoreDNS 副本每秒 1024 个数据包时，DNS 请求将被限制，导致 `unknownHostException` 错误。

#### 修复
要解决默认 coreDNS 的可扩展性问题，请考虑实施以下两个选项之一：
  * [启用 coreDNS 自动扩展](https://docs.aws.amazon.com/eks/latest/userguide/coredns-autoscaling.html)。
  * [实施节点本地缓存](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/)。

在扩展 `CoreDNS` 时，在不同节点之间分布副本也至关重要。在同一节点上共同定位 CoreDNS 将再次导致 ENI 限制，使额外的副本无效。为了在节点之间分布 `CoreDNS`，对 Pod 应用节点反亲和性策略：

```
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: k8s-app
          operator: In
          values:
          - kube-dns
      topologyKey: kubernetes.io/hostname
```

#### CoreDNS 监控
建议持续监控 CoreDNS 指标。有关详细信息，请参考 [EKS 网络最佳实践](https://docs.aws.amazon.com/eks/latest/best-practices/monitoring_eks_workloads_for_network_performance_issues.html#_monitoring_coredns_traffic_for_dns_throttling_issues)。

### DNS 查找和 ndots

在[具有默认 DNS 配置的 Kubernetes Pod](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) 中有一个如下所示的 `resolv.conf` 文件：

```
nameserver 10.100.0.10
search namespace.svc.cluster.local svc.cluster.local cluster.local ec2.internal
options ndots:5
```

`search` 行中列出的域名被附加到不是完全限定域名 (FQDN) 的 DNS 名称。例如，如果 Pod 尝试使用 `servicename.namespace` 连接到 Kubernetes 服务，域将按顺序附加，直到 DNS 名称匹配完整的 kubernetes 服务名称：

```
servicename.namespace.namespace.svc.cluster.local   <--- 失败，返回 NXDOMAIN
servicename.namespace.svc.cluster.local        <-- 成功
```

域是否完全限定由 resolv.conf 中的 `ndots` 选项确定。此选项定义在跳过 `search` 域之前域名中必须有的点数。这些额外的搜索可能会增加到外部资源（如 S3 和 RDS 端点）的连接延迟。

Kubernetes 中的默认 `ndots` 设置是五，如果您的应用程序不与集群中的其他 Pod 通信，我们可以将 `ndots` 设置为较低的值，如"2"。这是一个很好的起点，因为它仍然允许您的应用程序在同一命名空间和集群内的其他命名空间中进行服务发现，但允许像 `s3.us-east-2.amazonaws.com` 这样的域被识别为 FQDN（跳过 `search` 域）。

以下是来自 Kubernetes 文档的示例 Pod 清单，其中 `ndots` 设置为"2"：

```yaml
apiVersion: v1
kind: Pod
metadata:
  namespace: default
  name: dns-example
spec:
  containers:
    - name: test
      image: nginx
  dnsConfig:
    options:
      - name: ndots
        value: "2"
```

:::info

虽然在您的 Pod 部署中将 `ndots` 设置为"2"是一个合理的起点，但这不会在所有情况下普遍适用，不应在整个集群中应用。`ndots` 配置需要在 Pod 或 Deployment 级别配置。不建议在集群级别 CoreDNS 配置中减少此设置。

:::

### 跨可用区网络优化

某些工作负载可能需要在集群中的 Pod 之间交换数据，例如 Spark executor 在 shuffle 阶段期间。
如果 Pod 分布在多个可用区 (AZ) 中，此 shuffle 操作可能会变得非常昂贵，特别是在网络 I/O 方面。因此，对于这些工作负载，建议将 executor 或 worker Pod 共同定位在同一 AZ 中。在同一 AZ 中共同定位工作负载有两个主要目的：

* 减少跨 AZ 流量成本
* 减少 executor/Pod 之间的网络延迟

要让 Pod 共同定位在同一 AZ 上，我们可以使用基于 `podAffinity` 的调度约束。调度约束 `preferredDuringSchedulingIgnoredDuringExecution` 可以在 Pod 规范中强制执行。例如，在 Spark 中，我们可以为我们的 driver 和 executor Pod 使用自定义模板：

```yaml
spec:
  executor:
    affinity:
      podAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
              matchExpressions:
              - key: sparkoperator.k8s.io/app-name
                operator: In
                values:
                - <<spark-app-name>>
          topologyKey: topology.kubernetes.io/zone
          ...
```

您还可以利用 Kubernetes 拓扑感知路由，让 Kubernetes 服务在创建 Pod 后以更高效的方式路由流量：https://aws.amazon.com/blogs/containers/exploring-the-effect-of-topology-aware-hints-on-network-traffic-in-amazon-elastic-kubernetes-service/

:::info

将所有 executor 定位在单个 AZ 中，意味着该 AZ 将是*单点故障*。这是您应该在降低网络成本和延迟与 AZ 故障中断工作负载事件之间考虑的权衡。
如果您的工作负载在容量受限的实例上运行，您可能考虑使用多个 AZ 以避免容量不足错误。

:::
