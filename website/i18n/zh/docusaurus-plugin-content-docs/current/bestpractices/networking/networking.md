---
sidebar_label: VPC配置
---

# 数据网络

## VPC和IP考虑因素

### 为EKS集群中大量的IP地址使用进行规划。

AWS VPC CNI在EKS工作节点上维护一个IP地址的"预热池"，用于分配给Pod。当您的Pod需要更多IP地址时，CNI必须与EC2 API通信，将地址分配给您的节点。在高变化率或大规模扩展期间，这些EC2 API调用可能会受到速率限制，这将延迟Pod的配置，从而延迟工作负载的执行。在为您的环境设计VPC时，规划比您的pod更多的IP地址，以适应这个预热池。

使用默认VPC CNI配置，较大的节点将消耗更多的IP地址。例如，[一个运行10个pod的`m5.8xlarge`节点](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)将总共持有60个IP（以满足`WARM_ENI=1`）。然而，一个`m5.16xlarge`节点将持有100个IP。
配置VPC CNI以最小化这个预热池可能会增加来自您节点的EC2 API调用，并增加速率限制的风险。为这种额外的IP地址使用进行规划可以避免速率限制问题和管理IP地址使用。


### 如果您的IP空间受限，请考虑使用辅助CIDR。

如果您正在使用跨多个连接的VPC或站点的网络，可路由的地址空间可能有限。
例如，您的VPC可能限制为如下所示的小子网。在这个VPC中，如果不调整CNI配置，我们将无法运行超过一个`m5.16xlarge`节点。

![初始VPC](../../../../../../docs/bestpractices/networking/init-vpc.png)

您可以从不可跨VPC路由的范围（如RFC 6598范围，`100.64.0.0/10`）添加额外的VPC CIDR。在这种情况下，我们向VPC添加了`100.64.0.0/16`、`100.65.0.0/16`和`100.66.0.0/16`（因为这是最大的CIDR大小），然后使用这些CIDR创建了新的子网。
最后，我们在新的子网中重新创建了节点组，保留现有的EKS集群控制平面。

![扩展的VPC](../../../../../../docs/bestpractices/networking/expanded-vpc.png)

使用此配置，您仍然可以从连接的VPC与EKS集群控制平面通信，但您的节点和pod有足够的IP地址来适应您的工作负载和预热池。
## 调整VPC CNI

### VPC CNI和EC2速率限制

当启动EKS工作节点时，它最初有一个带有单个IP地址的ENI，用于EC2实例通信。当VPC CNI启动时，它尝试配置一个IP地址的预热池，可以分配给Kubernetes Pod（[EKS最佳实践指南中有更多详细信息](https://aws.github.io/aws-eks-best-practices/networking/vpc-cni/#overview)）。

VPC CNI必须进行AWS EC2 API调用（如`AssignPrivateIpV4Address`和`DescribeNetworkInterfaces`）来将这些额外的IP和ENI分配给工作节点。当EKS集群扩展节点或Pod数量时，这些EC2 API调用的数量可能会激增。这种调用激增可能会遇到来自EC2 API的速率限制，以帮助服务的性能，并确保所有Amazon EC2客户的公平使用。这种速率限制可能会导致IP地址池耗尽，而CNI尝试分配更多IP。

这些失败将导致如下所示的错误，表明由于VPC CNI无法配置IP地址，容器网络命名空间的配置失败。


```
Failed to create pod sandbox: rpc error: code = Unknown desc = failed to set up sandbox container "xxxxxxxxxxxxxxxxxxxxxx" network for pod "test-pod": networkPlugin cni failed to set up pod test-pod_default" network: add cmd: failed to assign an IP address to container
```

这种失败延迟了Pod的启动，并在重试此操作直到分配IP地址时给kubelet和工作节点增加了压力。为了避免这种延迟，您可以配置CNI以减少所需的EC2 API调用数量。


### 在大型集群或变化率高的集群中避免使用`WARM_IP_TARGET`

`WARM_IP_TARGET`可以帮助限制小型集群或pod变化率非常低的集群中的"浪费"IP。然而，在大型集群中需要仔细配置VPC CNI上的这个环境变量，因为它可能会增加EC2 API调用的数量，增加速率限制的风险和影响。

对于有大量Pod变化的集群，建议将`MINIMUM_IP_TARGET`设置为略高于您计划在每个节点上运行的预期pod数量的值。这将允许CNI在单个（或少数）调用中配置所有这些IP地址。

```hcl
  [...]

  # EKS Addons
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

### 使用`MAX_ENI`和`max-pods`限制大型实例类型上每个节点的IP数量

当使用较大的实例类型，如`16xlarge`或`24xlarge`时，[每个ENI可以分配的IP地址数量](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)可能相当大。例如，一个`c5.18xlarge`实例类型，使用默认CNI配置`WARM_ENI=1`，在运行少量pod时最终会持有100个IP地址（每个ENI 50个IP * 2个ENI）。

对于某些工作负载，CPU、内存或其他资源将限制该`c5.18xlarge`上的Pod数量，在我们需要超过50个IP之前。在这种情况下，您可能希望能够在该实例上最多运行30-40个pod。
```hcl
  [...]

  # EKS Addons
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


在CNI上设置`MAX_ENI=1`选项将限制每个节点能够配置的IP地址数量，但它不限制kubernetes将尝试调度到节点的pod数量。这可能导致pod被调度到无法配置更多IP地址的节点上。

要限制IP *和* 阻止k8s调度过多的pod，您需要：

1. 更新CNI配置环境变量，设置`MAX_ENI=1`
2. 更新工作节点上kubelet的`--max-pods`选项。

要配置--max-pods选项，您可以更新工作节点的用户数据，通过[bootstrap.sh脚本中的--kubelet -extra-args](https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh)设置此选项。默认情况下，此脚本为kubelet配置max-pods值，`--use-max-pods false`选项在提供自己的值时禁用此行为：

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

一个问题是每个ENI的IP数量根据实例类型而不同（[例如，`m5d.2xlarge`每个ENI可以有15个IP，而`m5d.4xlarge`每个ENI可以持有30个IP](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)）。这意味着为`max-pods`硬编码一个值可能会在更改实例类型或在混合实例环境中造成问题。

在EKS优化AMI版本中，[包含了一个脚本，可用于帮助计算AWS推荐的max-pods值](https://github.com/awslabs/amazon-eks-ami/blob/master/files/max-pods-calculator.sh)。如果您想为混合实例自动化此计算，您还需要更新实例的用户数据，使用`--instance-type-from-imds`标志从实例元数据自动发现实例类型。

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


#### Karpenter的Maxpods

默认情况下，Karpenter配置的节点将[根据节点实例类型](https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt)设置节点上的最大pod数。要如上所述配置`--max-pods`选项，可以通过在`.spec.kubeletConfiguration`中指定`maxPods`在Provisioner级别定义。此值将在Karpenter pod调度期间使用，并在kubelet启动时传递给`--max-pods`。

以下是Provisioner规范示例：

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
    - key: "karpenter.sh/capacity-type" # 如果不包括，AWS云提供商的webhook将默认为按需
      operator: In
      values: ["spot", "on-demand"]

  # Karpenter提供了指定一些额外Kubelet参数的能力。
  # 这些都是可选的，并为额外的自定义和用例提供支持。
  kubeletConfiguration:
    maxPods: 30
```
## 应用程序

### DNS查询和ndots

在[具有默认DNS配置的Kubernetes Pod](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)中，有一个如下所示的`resolv.conf`文件：

```
nameserver 10.100.0.10
search namespace.svc.cluster.local svc.cluster.local cluster.local ec2.internal
options ndots:5
```

`search`行中列出的域名会附加到不是完全限定域名(FQDN)的DNS名称上。例如，如果pod尝试使用`servicename.namespace`连接到Kubernetes服务，域名将按顺序附加，直到DNS名称匹配完整的kubernetes服务名称：

```
servicename.namespace.namespace.svc.cluster.local   <--- 失败，返回NXDOMAIN
servicename.namespace.svc.cluster.local        <-- 成功
```

域名是否完全限定由`resolv.conf`中的`ndots`选项决定。此选项定义了域名中必须有多少个点才能跳过`search`域。这些额外的搜索可能会增加连接到外部资源（如S3和RDS端点）的延迟。

Kubernetes中默认的`ndots`设置是5，如果您的应用程序不与集群中的其他pod通信，我们可以将`ndots`设置为较低的值，如"2"。这是一个很好的起点，因为它仍然允许您的应用程序在同一命名空间内和集群内的其他命名空间中进行服务发现，但允许像`s3.us-east-2.amazonaws.com`这样的域名被识别为FQDN（跳过`search`域）。

以下是Kubernetes文档中的一个示例pod清单，`ndots`设置为"2"：

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

虽然在pod部署中将`ndots`设置为"2"是一个合理的起点，但这并不适用于所有情况，不应该在整个集群范围内应用。`ndots`配置需要在Pod或Deployment级别配置。不建议在集群级别CoreDNS配置中减少此设置。

:::


### 跨可用区网络优化

某些工作负载可能需要在集群中的Pod之间交换数据，如Spark执行器在shuffle阶段。
如果Pod分布在多个可用区(AZ)，这种shuffle操作可能会非常昂贵，特别是在网络I/O方面。因此，对于这些工作负载，建议将执行器或工作器pod放在同一个AZ中。将工作负载放在同一个AZ中有两个主要目的：

* 减少跨AZ流量成本
* 减少执行器/Pod之间的网络延迟

要使pod位于同一个AZ，我们可以使用基于`podAffinity`的调度约束。调度约束`preferredDuringSchedulingIgnoredDuringExecution`可以在Pod规范中强制执行。例如，在Spark中，我们可以为驱动程序和执行器pod使用自定义模板：

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

您还可以利用Kubernetes拓扑感知路由，使Kubernetes服务在创建pod后以更有效的方式路由流量：https://aws.amazon.com/blogs/containers/exploring-the-effect-of-topology-aware-hints-on-network-traffic-in-amazon-elastic-kubernetes-service/

:::info

将所有执行器放在单一AZ中，意味着该AZ将是*单点故障*。这是您应该考虑的在降低网络成本和延迟与AZ故障中断工作负载事件之间的权衡。
如果您的工作负载在容量受限的实例上运行，您可能会考虑使用多个AZ以避免容量不足错误。

:::
