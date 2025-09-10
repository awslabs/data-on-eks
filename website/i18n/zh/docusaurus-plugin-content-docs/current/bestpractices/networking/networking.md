---
sidebar_label: VPC 配置
---

# 数据网络

## VPC 和 IP 考虑因素

### 默认 VPC CNI 配置
使用默认 VPC CNI 配置，较大的节点将消耗更多 IP 地址。例如，运行 10 个 Pod 的 [`m5.8xlarge` 节点](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI) 总共将持有 60 个 IP（以满足 `WARM_ENI_TARGET=1`）。然而，`m5.16xlarge` 节点将持有 100 个 IP。

AWS VPC CNI 在 EKS 工作节点上维护这个 IP 地址"预热池"以分配给 Pod。当您的 Pod 需要更多 IP 地址时，CNI 必须与 EC2 API 通信以将地址分配给您的节点。

### 为您的 EKS 集群规划大量 IP 地址使用。

在高变动或大规模扩展期间，这些 EC2 API 调用可能会受到速率限制，这将延迟 Pod 的配置，从而延迟工作负载的执行。此外，配置 VPC CNI 以最小化此预热池可能会增加来自节点的 EC2 API 调用并增加速率限制的风险。

### 如果您的 IP 空间受限，请考虑使用辅助 CIDR。

如果您正在使用跨多个连接的 VPC 或站点的网络，可路由地址空间可能有限。
例如，您的 VPC 可能限制为如下所示的小子网。在此 VPC 中，如果不调整 CNI 配置，我们将无法运行超过一个 `m5.16xlarge` 节点。

![初始 VPC](../../../../../../docs/bestpractices/networking/init-vpc.png)

您可以从不跨 VPC 路由的范围（如 RFC 6598 范围，`100.64.0.0/10`）添加额外的 VPC CIDR。在这种情况下，我们向 VPC 添加了 `100.64.0.0/16`、`100.65.0.0/16` 和 `100.66.0.0/16`（因为这是最大 CIDR 大小），然后使用这些 CIDR 创建了新子网。
最后，我们在新子网中重新创建了节点组，保留现有的 EKS 集群控制平面。

![扩展的 VPC](../../../../../../docs/bestpractices/networking/expanded-vpc.png)

使用此配置，您仍然可以从连接的 VPC 与 EKS 集群控制平面通信，但您的节点和 Pod 有足够的 IP 地址来容纳您的工作负载和预热池。

## 调整 VPC CNI

### VPC CNI 和 EC2 速率限制

当 EKS 工作节点启动时，它最初有一个单独的 ENI，附加了一个单独的 IP 地址供 EC2 实例通信。当 VPC CNI 启动时，它尝试配置一个可以分配给 Kubernetes Pod 的 IP 地址预热池（[EKS 最佳实践指南中的更多详细信息](https://aws.github.io/aws-eks-best-practices/networking/vpc-cni/#overview)）。

VPC CNI 必须进行 AWS EC2 API 调用（如 `AssignPrivateIpV4Address` 和 `DescribeNetworkInterfaces`）以将这些额外的 IP 和 ENI 分配给工作节点。当 EKS 集群扩展节点或 Pod 数量时，这些 EC2 API 调用的数量可能会激增。这种调用激增可能会遇到来自 EC2 API 的速率限制，以帮助服务性能，并确保所有 Amazon EC2 客户的公平使用。这种速率限制可能导致 IP 地址池耗尽，而 CNI 尝试分配更多 IP。

这些失败将导致如下错误，表明容器网络命名空间的配置失败，因为 VPC CNI 无法配置 IP 地址。

```
Failed to create pod sandbox: rpc error: code = Unknown desc = failed to set up sandbox container "xxxxxxxxxxxxxxxxxxxxxx" network for pod "test-pod": networkPlugin cni failed to set up pod test-pod_default" network: add cmd: failed to assign an IP address to container
```

此失败延迟了 Pod 的启动，并给 kubelet 和工作节点增加了压力，因为此操作会重试直到分配 IP 地址。为了避免此延迟，您可以配置 CNI 以减少所需的 EC2 API 调用数量。
