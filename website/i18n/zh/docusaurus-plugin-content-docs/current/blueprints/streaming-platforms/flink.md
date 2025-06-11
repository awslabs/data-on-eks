---
title: Flink Operator on EKS
sidebar_position: 3
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

:::info
请注意，我们正在为此蓝图添加更多功能，如带有多个连接器的Flink示例、WebUI的Ingress、Grafana仪表板等。
:::

## Apache Flink简介
[Apache Flink](https://flink.apache.org/)是一个开源的统一流处理和批处理框架，设计用于处理大量数据。它提供快速、可靠和可扩展的数据处理，具有容错能力和精确一次语义。
Flink的一些关键特性是：
- **分布式处理**：Flink设计为以分布式方式处理大量数据，使其具有水平可扩展性和容错性。
- **流处理和批处理**：Flink为流处理和批处理提供API。这意味着您可以实时处理数据，或者批量处理数据。
- **容错性**：Flink内置了处理节点故障、网络分区和其他类型故障的机制。
- **精确一次语义**：Flink支持精确一次处理，确保每条记录只处理一次，即使在出现故障的情况下也是如此。
- **低延迟**：Flink的流引擎针对低延迟处理进行了优化，使其适用于需要实时处理数据的用例。
- **可扩展性**：Flink提供了丰富的API和库，使其易于扩展和定制以适应您的特定用例。

## 架构

Flink架构与EKS的高级设计。

![Flink设计UI](../../../../../../docs/blueprints/streaming-platforms/img/flink-design.png)

## Flink Kubernetes operator
[Flink Kubernetes operator](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/)是一个强大的工具，用于在Kubernetes上管理Flink集群。Flink Kubernetes operator（ operator）作为控制平面，管理Apache Flink应用程序的完整部署生命周期。 operator可以使用Helm安装在Kubernetes集群上。Flink operator的核心职责是管理Flink应用程序的完整生产生命周期。
1. 运行、暂停和删除应用程序
2. 有状态和无状态应用程序升级
3. 触发和管理保存点
4. 处理错误，回滚损坏的升级

Flink operator定义了两种类型的自定义资源(CR)，它们是Kubernetes API的扩展。

<Tabs>
<TabItem value="FlinkDeployment" label="FlinkDeployment">


**FlinkDeployment**
- FlinkDeployment CR定义了**Flink应用程序**和**会话集群**部署。
- 应用程序部署在应用程序模式下管理专用Flink集群上的单个作业部署。
- 会话集群允许您在现有会话集群上运行多个Flink作业。

    <details>
    <summary>应用程序模式下的FlinkDeployment，点击切换内容！</summary>

    ```yaml
    apiVersion: flink.apache.org/v1beta1
    kind: FlinkDeployment
    metadata:
    namespace: default
    name: basic-example
    spec:
    image: flink:1.16
    flinkVersion: v1_16
    flinkConfiguration:
        taskmanager.numberOfTaskSlots: "2"
    serviceAccount: flink
    jobManager:
        resource:
        memory: "2048m"
        cpu: 1
    taskManager:
        resource:
        memory: "2048m"
        cpu: 1
    job:
        jarURI: local://opt/flink/examples/streaming/StateMachineExample.jar
        parallelism: 2
        upgradeMode: stateless
        state: running
    ```
    </details>

</TabItem>

<TabItem value="FlinkSessionJob" label="FlinkSessionJob">

**FlinkSessionJob**
- `FlinkSessionJob` CR定义了**会话集群**上的会话作业，每个会话集群可以运行多个`FlinkSessionJob`。
- 会话部署管理Flink会话集群，但不为其提供任何作业管理

    <details>
    <summary>使用现有的"basic-session-cluster"会话集群部署的FlinkSessionJob</summary>

    ```yaml
    apiVersion: flink.apache.org/v1beta1
    kind: FlinkSessionJob
    metadata:
    name: basic-session-job-example
    spec:
    deploymentName: basic-session-cluster
    job:
        jarURI: https://repo1.maven.org/maven2/org/apache/flink/flink-examples-streaming_2.12/1.15.3/flink-examples-streaming_2.12-1.15.3-TopSpeedWindowing.jar
        parallelism: 4
        upgradeMode: stateless
    ```

    </details>

</TabItem>
</Tabs>

:::info
会话集群使用与应用程序集群类似的规范，唯一的区别是在yaml规范中没有定义`job`。
:::

:::info
根据Flink文档，建议在生产环境中使用应用程序模式的FlinkDeployment。
:::

除了部署类型外，Flink Kubernetes operator还支持两种部署模式：`Native`和`Standalone`。

<Tabs>
<TabItem value="Native" label="Native">

**Native**

- Native集群部署是默认的部署模式，在部署集群时使用Flink内置的与Kubernetes集成。
- Flink集群直接与Kubernetes通信，允许它管理Kubernetes资源，例如动态分配和释放TaskManager pod。
- Flink Native对于想要构建自己的集群管理系统或与现有管理系统集成的高级用户很有用。
- Flink Native在作业调度和执行方面提供了更大的灵活性。
- 对于标准 operator使用，建议在Native模式下运行您自己的Flink作业。

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
...
spec:
...
mode: native
```
</TabItem>

<TabItem value="Standalone" label="Standalone">

**Standalone**

- Standalone集群部署只是将Kubernetes作为Flink集群运行的编排平台。
- Flink不知道它在Kubernetes上运行，因此所有Kubernetes资源需要由Kubernetes operator外部管理。

    ```yaml
    apiVersion: flink.apache.org/v1beta1
    kind: FlinkDeployment
    ...
    spec:
    ...
    mode: standalone
    ```

</TabItem>
</Tabs>

## 在Kubernetes上运行Flink作业的最佳实践
要充分利用Kubernetes上的Flink，以下是一些最佳实践：

- **使用Kubernetes operator**：安装并使用Flink Kubernetes operator来自动化Flink集群在Kubernetes上的部署和管理。
- **在专用命名空间中部署**：为Flink Kubernetes operator创建一个单独的命名空间，为Flink作业/工作负载创建另一个命名空间。这确保Flink作业是隔离的，并拥有自己的资源。
- **使用高质量存储**：将Flink检查点和保存点存储在高质量存储中，如Amazon S3或其他持久外部存储。这些存储选项可靠、可扩展，并为大量数据提供持久性。
- **优化资源分配**：为Flink作业分配足够的资源以确保最佳性能。这可以通过为Flink容器设置资源请求和限制来完成。
- **适当的网络隔离**：使用Kubernetes网络策略将Flink作业与在同一Kubernetes集群上运行的其他工作负载隔离。这确保Flink作业具有所需的网络访问权限，而不受其他工作负载的影响。
- **最佳配置Flink**：根据您的用例调整Flink设置。例如，调整Flink的并行度设置，确保Flink作业根据输入数据的大小适当扩展。
- **使用检查点和保存点**：使用检查点进行Flink应用程序状态的定期快照，使用保存点进行更高级的用例，如升级或降级应用程序。
- **将检查点和保存点存储在正确的位置**：将检查点存储在分布式文件系统或键值存储中，如Amazon S3或其他持久外部存储。将保存点存储在持久外部存储中，如Amazon S3。

## Flink升级
Flink operator为Flink作业提供了三种升级模式。查看[Flink升级文档](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/docs/custom-resource/job-management/#stateful-and-stateless-application-upgrades)获取最新信息。

1. **stateless**：从空状态进行无状态应用程序升级
2. **last-state**：在任何应用程序状态下快速升级（即使对于失败的作业），不需要健康的作业，因为它总是使用最新的检查点信息。如果HA元数据丢失，可能需要手动恢复。
3. **savepoint**：使用保存点进行升级，提供最大的安全性和可能作为备份/分叉点。保存点将在升级过程中创建。请注意，Flink作业需要运行才能允许创建保存点。如果作业处于不健康状态，将使用最后一个检查点（除非kubernetes.operator.job.upgrade.last-state-fallback.enabled设置为false）。如果最后一个检查点不可用，作业升级将失败。

:::info
`last-state`或`savepoint`是生产环境推荐的模式
:::


<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/streaming/flink)中，您将配置运行带有Flink operator和Apache YuniKorn的Flink作业所需的以下资源。

此示例将运行Flink operator的EKS集群部署到新的VPC中。

- 创建一个新的示例VPC，2个私有子网和2个公共子网
- 为公共子网创建互联网网关，为私有子网创建NAT网关
- 创建具有公共端点的EKS集群控制平面（仅用于演示目的），带有核心托管节点组、按需节点组和用于Flink工作负载的Spot节点组
- 部署指标服务器、集群自动扩展器、Apache YuniKorn、Karpenter、Grafana、AMP和Prometheus服务器
- 部署Cert Manager和Flink operator附加组件。Flink operator依赖于Cert Manager
- 创建新的Flink数据团队资源，包括命名空间、服务账户、IRSA、角色和角色绑定
- 为不同计算类型部署三个Karpenter配置器

### 先决条件

确保您已在机器上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库。

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到Flink的Terraform模板目录并运行`install.sh`脚本。

```bash
cd data-on-eks/streaming/flink
chmod +x install.sh
./install.sh
```

验证集群状态

```bash
    ➜ kubectl get nodes -A
    NAME                                         STATUS   ROLES    AGE   VERSION
    ip-10-1-160-150.us-west-2.compute.internal   Ready    <none>   24h   v1.24.11-eks-a59e1f0
    ip-10-1-169-249.us-west-2.compute.internal   Ready    <none>   6d    v1.24.11-eks-a59e1f0
    ip-10-1-69-244.us-west-2.compute.internal    Ready    <none>   6d    v1.24.11-eks-a59e1f0

    ➜  ~ kubectl get pods -n flink-kubernetes-operator
    NAME                                         READY   STATUS    RESTARTS   AGE
    flink-kubernetes-operator-77697fb949-rwqqm   2/2     Running   0          24h

    ➜  ~ kubectl get pods -n cert-manager
    NAME                                      READY   STATUS    RESTARTS   AGE
    cert-manager-77fc7548dc-dzdms             1/1     Running   0          24h
    cert-manager-cainjector-8869b7ff7-4w754   1/1     Running   0          24h
    cert-manager-webhook-586ddf8589-g6s87     1/1     Running   0          24h
```

列出为Flink团队创建的所有资源，以便使用此命名空间运行Flink作业

```bash
    ➜  ~ kubectl get all,role,rolebinding,serviceaccount --namespace flink-team-a-ns
    NAME                                               CREATED AT
    role.rbac.authorization.k8s.io/flink-team-a-role   2023-04-06T13:17:05Z

    NAME                                                              ROLE                     AGE
    rolebinding.rbac.authorization.k8s.io/flink-team-a-role-binding   Role/flink-team-a-role   22h

    NAME                             SECRETS   AGE
    serviceaccount/default           0         22h
    serviceaccount/flink-team-a-sa   0         22h
```

</CollapsibleContent>


<CollapsibleContent header={<h2><span>使用Karpenter执行示例Flink作业</span></h2>}>

导航到示例目录并提交Flink作业。

```bash
cd data-on-eks/streaming/flink/examples/karpenter
kubectl apply -f flink-sample-job.yaml
```

使用以下命令监控作业状态。
您应该看到由karpenter触发的新节点，YuniKorn将在此节点上调度一个Job manager pod和一个Taskmanager pod。

```bash
kubectl get deployments -n flink-team-a-ns
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
basic-example   1/1     1            1           5m9s

kubectl get pods -n flink-team-a-ns
NAME                            READY   STATUS    RESTARTS   AGE
basic-example-bf467dff7-zwhgc   1/1     Running   0          102s
basic-example-taskmanager-1-1   1/1     Running   0          87s
basic-example-taskmanager-1-2   1/1     Running   0          87s

kubectl get services -n flink-team-a-ns
NAME                 TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
basic-example-rest   ClusterIP   172.20.74.9   <none>        8081/TCP   3m43s
```

要访问作业的Flink WebUI，在本地运行此命令。

```bash
kubectl port-forward svc/basic-example-rest 8081 -n flink-team-a-ns
```

![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink1.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink2.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink3.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink4.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink5.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>使用托管节点组和集群自动扩展器执行示例Flink作业</span></h2>}>

导航到示例目录并提交Spark作业。

```bash
cd data-on-eks/streaming/flink/examples/cluster-autoscaler
kubectl apply -f flink-sample-job.yaml
```

使用以下命令监控作业状态。
您应该看到由集群自动扩展器触发的新节点，YuniKorn将在此节点上调度一个Job manager pod和一个Taskmanager pod。

```bash
kubectl get deployments -n flink-team-a-ns
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
basic-example   1/1     1            1           5m9s

kubectl get pods -n flink-team-a-ns
NAME                            READY   STATUS    RESTARTS   AGE
basic-example-bf467dff7-zwhgc   1/1     Running   0          102s
basic-example-taskmanager-1-1   1/1     Running   0          87s
basic-example-taskmanager-1-2   1/1     Running   0          87s

kubectl get services -n flink-team-a-ns
NAME                 TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
basic-example-rest   ClusterIP   172.20.74.9   <none>        8081/TCP   3m43s
```

要访问作业的Flink WebUI，在本地运行此命令。

```bash
kubectl port-forward svc/basic-example-rest 8081 -n flink-team-a-ns
```

![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink1.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink2.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink3.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink4.png)
![Flink作业UI](../../../../../../docs/blueprints/streaming-platforms/img/flink5.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/streaming/flink && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源
:::
