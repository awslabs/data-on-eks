---
sidebar_position: 3
title: 使用 Flink Streaming 的 EMR on EKS
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

:::info
请注意，我们正在为此蓝图添加更多功能，例如具有多个连接器的 Flink 示例、WebUI 的 Ingress、Grafana 仪表板等。
:::

## Apache Flink 介绍
[Apache Flink](https://flink.apache.org/) 是一个开源的统一流处理和批处理框架，旨在处理大量数据。它提供快速、可靠和可扩展的数据处理，具有容错性和精确一次语义。
Flink 的一些关键功能包括：
- **分布式处理**：Flink 旨在以分布式方式处理大量数据，使其具有水平可扩展性和容错性。
- **流处理和批处理**：Flink 为流处理和批处理提供 API。这意味着您可以在生成数据时实时处理数据，或批量处理数据。
- **容错性**：Flink 具有处理节点故障、网络分区和其他类型故障的内置机制。
- **精确一次语义**：Flink 支持精确一次处理，确保每条记录都被精确处理一次，即使在出现故障的情况下也是如此。
- **低延迟**：Flink 的流引擎针对低延迟处理进行了优化，使其适用于需要实时数据处理的用例。
- **可扩展性**：Flink 提供丰富的 API 和库集，使其易于扩展和自定义以适合您的特定用例。

## 架构

Flink 架构与 EKS 的高级设计。

![Flink Design UI](../../../../../../docs/blueprints/streaming-platforms/img/flink-design.png)

## EMR on EKS Flink Kubernetes Operator
Amazon EMR 6.13.0 及更高版本支持带有 Apache Flink 的 Amazon EMR on EKS，或 ![EMR Flink Kubernetes operator](https://gallery.ecr.aws/emr-on-eks/flink-kubernetes-operator)，作为 Amazon EMR on EKS 的作业提交模型。使用带有 Apache Flink 的 Amazon EMR on EKS，您可以在自己的 Amazon EKS 集群上使用 Amazon EMR 发布运行时部署和管理 Flink 应用程序。在 Amazon EKS 集群中部署 Flink Kubernetes operator 后，您可以直接使用该 operator 提交 Flink 应用程序。operator 管理 Flink 应用程序的生命周期。
1. 运行、暂停和删除应用程序
2. 有状态和无状态应用程序升级
3. 触发和管理保存点
4. 处理错误，回滚损坏的升级

除了上述功能外，EMR Flink Kubernetes operator 还提供以下附加功能：
1. 使用 Amazon S3 中的 jar 启动 Flink 应用程序
2. 与 Amazon S3 和 Amazon CloudWatch 的监控集成以及容器日志轮换。
3. 根据观察到的指标的历史趋势自动调整自动扩展器配置。
4. 在扩展或故障恢复期间更快的 Flink 作业重启
5. IRSA（服务账户的 IAM 角色）原生集成
6. Pyflink 支持

Flink Operator 定义了两种类型的自定义资源 (CR)，它们是 Kubernetes API 的扩展。

<Tabs>
<TabItem value="FlinkDeployment" label="FlinkDeployment">

**FlinkDeployment**
- FlinkDeployment CR 定义 **Flink Application** 和 **Session Cluster** 部署。
- 应用程序部署在应用程序模式下管理专用 Flink 集群上的单个作业部署。
- 会话集群允许您在现有会话集群上运行多个 Flink 作业。

    <details>
    <summary>应用程序模式下的 FlinkDeployment，点击切换内容！</summary>

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
        jarURI: local:///opt/flink/examples/streaming/StateMachineExample.jar
        parallelism: 2
        upgradeMode: stateless
        state: running
    ```
    </details>

</TabItem>

<TabItem value="FlinkSessionJob" label="FlinkSessionJob">

**FlinkSessionJob**
- `FlinkSessionJob` CR 定义 **Session cluster** 上的会话作业，每个会话集群可以运行多个 `FlinkSessionJob`。
- 会话部署管理 Flink 会话集群，而不为其提供任何作业管理

    <details>
    <summary>使用现有"basic-session-cluster"会话集群部署的 FlinkSessionJob</summary>

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
会话集群使用与应用程序集群类似的规范，唯一的区别是在 yaml 规范中未定义 `job`。
:::

:::info
根据 Flink 文档，建议在生产环境中使用应用程序模式下的 FlinkDeployment。
:::

除了部署类型之外，Flink Kubernetes Operator 还支持两种部署模式：`Native` 和 `Standalone`。

<Tabs>
<TabItem value="Native" label="Native">

**Native**

- 原生集群部署是默认部署模式，在部署集群时使用 Flink 与 Kubernetes 的内置集成。
- Flink 集群直接与 Kubernetes 通信，允许它管理 Kubernetes 资源，例如动态分配和取消分配 TaskManager Pod。
- Flink Native 对于想要构建自己的集群管理系统或与现有管理系统集成的高级用户很有用。
- Flink Native 在作业调度和执行方面提供更大的灵活性。
- 对于标准 Operator 使用，建议在 Native 模式下运行您自己的 Flink 作业。

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

- 独立集群部署简单地使用 Kubernetes 作为 Flink 集群运行的编排平台。
- Flink 不知道它在 Kubernetes 上运行，因此所有 Kubernetes 资源都需要由 Kubernetes Operator 外部管理。

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

## 在 Kubernetes 上运行 Flink 作业的最佳实践
要充分利用 Kubernetes 上的 Flink，以下是一些要遵循的最佳实践：

- **使用 Kubernetes Operator**：安装并使用 Flink Kubernetes Operator 来自动化 Kubernetes 上 Flink 集群的部署和管理。
- **在专用命名空间中部署**：为 Flink Kubernetes Operator 创建一个单独的命名空间，为 Flink 作业/工作负载创建另一个命名空间。这确保 Flink 作业被隔离并拥有自己的资源。
- **使用高质量存储**：将 Flink 检查点和保存点存储在高质量存储中，如 Amazon S3 或其他持久外部存储。这些存储选项可靠、可扩展，并为大量数据提供持久性。
- **优化资源分配**：为 Flink 作业分配足够的资源以确保最佳性能。这可以通过为 Flink 容器设置资源请求和限制来完成。
- **适当的网络隔离**：使用 Kubernetes 网络策略将 Flink 作业与在同一 Kubernetes 集群上运行的其他工作负载隔离。这确保 Flink 作业具有所需的网络访问权限，而不会受到其他工作负载的影响。
- **优化配置 Flink**：根据您的用例调整 Flink 设置。例如，调整 Flink 的并行度设置，以确保 Flink 作业根据输入数据的大小适当扩展。
- **使用检查点和保存点**：使用检查点进行 Flink 应用程序状态的定期快照，使用保存点进行更高级的用例，如升级或降级应用程序。
- **在正确的位置存储检查点和保存点**：将检查点存储在分布式文件系统或键值存储中，如 Amazon S3 或其他持久外部存储。将保存点存储在持久外部存储中，如 Amazon S3。

## Flink 升级
Flink Operator 为 Flink 作业提供三种升级模式。查看 [Flink 升级文档](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/docs/custom-resource/job-management/#stateful-and-stateless-application-upgrades) 获取最新信息。

1. **stateless**：从空状态进行无状态应用程序升级
2. **last-state**：在任何应用程序状态下快速升级（即使对于失败的作业），不需要健康的作业，因为它始终使用最新的检查点信息。如果 HA 元数据丢失，可能需要手动恢复。
3. **savepoint**：使用保存点进行升级，提供最大的安全性和作为备份/分叉点的可能性。保存点将在升级过程中创建。请注意，Flink 作业需要运行才能创建保存点。如果作业处于不健康状态，将使用最后一个检查点（除非 kubernetes.operator.job.upgrade.last-state-fallback.enabled 设置为 false）。如果最后一个检查点不可用，作业升级将失败。

:::info
建议在生产中使用 `last-state` 或 `savepoint` 模式
:::

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/streaming/flink)中，您将配置使用 Flink Operator 和 Apache YuniKorn 运行 Flink 作业所需的以下资源。

此示例将运行 Flink Operator 的 EKS 集群部署到新的 VPC 中。

- 创建新的示例 VPC、2 个私有子网和 2 个公有子网
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关
- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的），包含核心托管节点组、按需节点组和用于 Flink 工作负载的 Spot 节点组
- 部署 Metrics server、Cluster Autoscaler、Apache YuniKorn、Karpenter、Grafana、AMP 和 Prometheus server
- 部署 Cert Manager 和 EMR Flink Operator。Flink Operator 依赖于 Cert Manager
- 创建新的 Flink 数据团队资源，包括命名空间、IRSA、角色和角色绑定
- 为 flink-compute-optimized 类型部署 Karpenter provisioner

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆存储库。

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到 Flink 的 Terraform 模板目录并运行 `install.sh` 脚本。

```bash
cd data-on-eks/streaming/emr-flink-eks
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

    ➜  ~ kubectl get pods -n flink-kubernetes-operator-ns
    NAME                                         READY   STATUS    RESTARTS   AGE
    flink-kubernetes-operator-555776785f-pzx8p   2/2     Running   0          4h21m
    flink-kubernetes-operator-555776785f-z5jpt   2/2     Running   0          4h18m

    ➜  ~ kubectl get pods -n cert-manager
    NAME                                      READY   STATUS    RESTARTS   AGE
    cert-manager-77fc7548dc-dzdms             1/1     Running   0          24h
    cert-manager-cainjector-8869b7ff7-4w754   1/1     Running   0          24h
    cert-manager-webhook-586ddf8589-g6s87     1/1     Running   0          24h
```

列出为 Flink 团队创建的所有资源，以使用此命名空间运行 Flink 作业

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

<CollapsibleContent header={<h2><span>使用 Karpenter 执行示例 Flink 作业</span></h2>}>

导航到示例目录并提交 Flink 作业。

```bash
cd data-on-eks/streaming/emr-eks-flink/examples/karpenter
```
获取链接到作业执行服务账户的角色 arn。
```bash
terraform output flink_job_execution_role_arn
```
获取用于检查点、保存点、日志和作业存储数据的 S3 存储桶名称。
```bash
terraform output flink_operator_bucket
```

在任何编辑器中打开 basic-example-app-cluster.yaml，并将 **JOB_EXECUTION_ROLE_ARN** 的占位符替换为 flink_job_execution_role_arn terraform 输出命令。将 **ENTER_S3_BUCKET** 占位符替换为 flink_operator_bucket 输出。

通过运行 kubectl deploy 命令部署作业。

```bash
kubectl apply -f basic-example-app-cluster.yaml
```

使用以下命令监控作业状态。
您应该看到由 karpenter 触发的新节点，YuniKorn 将在此节点上调度一个作业管理器 Pod 和一个任务管理器 Pod。

```bash
kubectl get deployments -n flink-team-a-ns
NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
basic-example-app-cluster-flink   2/2     2            2           3h6m

kubectl get pods -n flink-team-a-ns
NAME                                               READY   STATUS    RESTARTS   AGE
basic-example-app-cluster-flink-7c7d9c6fd9-cdfmd   2/2     Running   0          3h7m
basic-example-app-cluster-flink-7c7d9c6fd9-pjxj2   2/2     Running   0          3h7m
basic-example-app-cluster-flink-taskmanager-1-1    2/2     Running   0          3h6m

kubectl get services -n flink-team-a-ns
NAME                                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
basic-example-app-cluster-flink-rest   ClusterIP   172.20.17.152   <none>        8081/TCP   3h7m
```

要访问作业的 Flink WebUI，请在本地运行此命令。

```bash
kubectl port-forward svc/basic-example-app-cluster-flink-rest 8081 -n flink-team-a-ns
```

![Flink Job UI](../../../../../../docs/blueprints/streaming-platforms/img/flink1.png)
![Flink Job UI](../../../../../../docs/blueprints/streaming-platforms/img/flink2.png)
![Flink Job UI](../../../../../../docs/blueprints/streaming-platforms/img/flink3.png)
![Flink Job UI](../../../../../../docs/blueprints/streaming-platforms/img/flink4.png)
![Flink Job UI](../../../../../../docs/blueprints/streaming-platforms/img/flink5.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用 `-target` 选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd .. && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源
:::
