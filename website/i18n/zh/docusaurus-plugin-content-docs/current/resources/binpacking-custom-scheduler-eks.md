---
sidebar_position: 4
sidebar_label: Amazon EKS 的装箱调度
---

# Amazon EKS 的装箱调度

## 介绍
在这篇文章中，我们将向您展示如何在运行 DoEKS 时为 Amazon EKS 启用自定义调度器，特别是对于 EKS 上的 Spark，包括 OSS Spark 和 EMR on EKS。自定义调度器是在数据平面中运行的具有 ```MostAllocated``` 策略的自定义 Kubernetes 调度器。

### 为什么要装箱调度
默认情况下，[scheduling-plugin](https://kubernetes.io/docs/reference/scheduling/config/#scheduling-plugins) NodeResourcesFit 使用 ```LeastAllocated``` 作为评分策略。对于长时间运行的工作负载，这很好，因为具有高可用性。但对于批处理作业，如 Spark 工作负载，这会导致高成本。通过从 ```LeastAllocated``` 更改为 ```MostAllocated```，它避免了将 Pod 分散到所有运行的节点上，从而提高资源利用率和更好的成本效率。

像 Spark 这样的批处理作业按需运行，时间有限或可预测。使用 ```MostAllocated``` 策略，Spark 执行器总是装箱到一个节点中，直到该节点无法托管任何 Pod。您可以看到下图显示了 EMR on EKS 中的 ```MostAllocated```。

![img.png](../../../../../docs/resources/img/binpack_singlejob.gif)

EMR on EKS 中的 ```LeastAllocated```

![img.png](../../../../../docs/resources/img/no_binpacking.gif)

### 优点
1) 提高节点利用率
2) 节省成本

### 考虑因素
虽然我们提供了升级指导、支持矩阵和高可用性设计，但在数据平面中维护自定义调度器需要努力，包括：
1) 升级操作。计划与批处理作业一起升级，确保调度器按预期运行。
2) 监控调度器。生产目的需要监控和警报。
3) 根据您的要求调整调度器 Pod 资源和其他自定义。

## 部署解决方案

### 克隆存储库

```shell
git clone https://github.com/aws-samples/custom-scheduler-eks
cd custom-scheduler-eks
```

### 清单

**Amazon EKS 1.24**

```shell
kubectl apply -f deploy/manifests/custom-scheduler/amazon-eks-1.24-custom-scheduler.yaml
