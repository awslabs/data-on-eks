---
title: Ray Serve高可用性
sidebar_position: 6
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::danger

注意：Mistral-7B-Instruct-v0.2是[Huggingface](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2)仓库中的一个受限模型。要使用此模型，需要使用HuggingFace令牌。
要在HuggingFace中生成令牌，请使用您的HuggingFace账户登录，并在[设置](https://huggingface.co/settings/tokens)页面上点击`访问令牌`菜单项。

:::

## 使用Elastic Cache for Redis实现Ray头节点高可用性

Ray集群的一个关键组件是头节点，它通过管理任务调度、状态同步和节点协调来编排整个集群。然而，默认情况下，Ray头部Pod代表一个单点故障；如果它失败，包括Ray工作节点Pod在内的整个集群都需要重新启动。

为了解决这个问题，Ray头节点的高可用性(HA)至关重要。全局控制服务(GCS)管理RayCluster中的集群级元数据。默认情况下，GCS缺乏容错能力，因为它将所有数据存储在内存中，故障可能导致整个Ray集群失败。为了避免这种情况，必须为Ray的全局控制存储(GCS)添加容错能力，这允许Ray Serve应用程序在头节点崩溃时继续提供流量。在GCS重新启动的情况下，它从Redis实例检索所有数据并恢复其常规功能。

![Ray-head-worker-redis](../../../../../../../docs/gen-ai/inference/img/ray-head-ha-1.png)

![Ray-head-ha](../../../../../../../docs/gen-ai/inference/img/ray-head-ha-2.png)

以下部分提供了如何启用GCS容错并确保Ray头部Pod高可用性的步骤。我们使用`Mistral-7B-Instruct-v0.2`模型来演示Ray头部高可用性。

### 添加外部Redis服务器

GCS容错需要一个外部Redis数据库。您可以选择托管自己的Redis数据库，或者通过第三方供应商使用一个。

对于开发和测试目的，您还可以在与Ray集群相同的EKS集群上托管容器化的Redis数据库。但是，对于生产设置，建议使用高可用的外部Redis集群。在这个模式中，我们使用了[Amazon ElasticCache for Redis](https://aws.amazon.com/elasticache/redis/)来创建一个外部Redis集群。您也可以选择使用[Amazon memoryDB](https://aws.amazon.com/memorydb/)来设置Redis集群。

作为当前蓝图的一部分，我们添加了一个名为`elasticache`的terraform模块，它在AWS中创建一个Elastic Cache Redis集群。这使用了禁用集群模式的Redis集群，包含一个节点。这个集群节点的端点可以用于读取和写入。

在此模块中需要注意的关键事项是 -

- Redis集群与EKS集群在同一个VPC中。如果Redis集群创建在单独的VPC中，则需要在EKS集群VPC和Elastic Cache Redis集群VPC之间设置VPC对等连接，以启用网络连接。
- 在创建Redis集群时需要创建一个缓存子网组。子网组是您可能希望在VPC中为缓存指定的子网集合。ElastiCache使用该缓存子网组将IP地址分配给缓存中的每个缓存节点。蓝图自动将EKS集群使用的所有子网添加到Elastic cache Redis集群的子网组中。
- 安全组 - 分配给Redis缓存的安全组需要有一个入站规则，允许来自EKS集群工作节点安全组的TCP流量通过端口6379到达Redis集群安全组。这是因为Ray头部Pod需要通过端口6379与Elastic cache Redis集群建立连接。蓝图自动设置带有入站规则的安全组。
要使用Amazon Elastic Cache创建Redis集群，请按照以下步骤操作。

:::info

这个Mistral7b部署使用具有高可用性的Ray Serve。如果您已经在之前的步骤中部署了mistral7b，那么您可以删除该部署并运行以下步骤。

:::

**先决条件**：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [envsubst](https://pypi.org/project/envsubst/)
5. [jq](https://jqlang.github.io/jq/download/)

首先，通过运行以下命令将`enable_rayserve_ha_elastic_cache_redis`变量设置为`true`来启用Redis集群的创建。默认情况下，它设置为`false`。

```bash
export TF_VAR_enable_rayserve_ha_elastic_cache_redis=true
```

然后，运行`install.sh`脚本来安装带有KubeRay operator和其他附加组件的EKS集群。

```bash
cd data-on-eks/ai-ml/trainimum-inferentia
./install.sh
```

除了EKS集群外，此蓝图还创建了一个AWS Elastic Cache Redis集群。示例输出如下所示

```text
Apply complete! Resources: 8 added, 1 changed, 0 destroyed.

Outputs:

configure_kubectl = "aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia"
elastic_cache_redis_cluster_arn = "arn:aws:elasticache:us-west-2:11111111111:cluster:trainium-inferentia"
```

### 将外部Redis信息添加到RayService

一旦创建了elastic cache Redis集群，我们需要修改`mistral-7b`模型推理的`RayService`配置。

首先，我们需要使用AWS CLI和jq获取Elastic Cache Redis集群端点，如下所示。

```bash
export EXT_REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id "trainium-inferentia" \
    --show-cache-node-info | jq -r '.CacheClusters[0].CacheNodes[0].Endpoint.Address')
```

现在，在`RayService` CRD下添加注解`ray.io/ft-enabled: "true"`。当设置为`true`时，注解`ray.io/ft-enabled`启用GCS容错。

```yaml
apiVersion: ray.io/v1
kind: RayService
metadata:
  name: mistral
  namespace: mistral
  annotations:
    ray.io/ft-enabled: "true"
```

在`headGroupSpec`中添加外部Redis集群信息作为`RAY_REDIS_ADDRESS`环境变量。

```yaml
headGroupSpec:
  headService:
    metadata:
      name: mistral
      namespace: mistral
  rayStartParams:
    dashboard-host: '0.0.0.0'
    num-cpus: "0"
  template:
    spec:
      containers:
      - name: head
        ....
        env:
          - name: RAY_REDIS_ADDRESS
            value: $EXT_REDIS_ENDPOINT:6379
```

`RAY_REDIS_ADDRESS`的值应该是您的Redis数据库的地址。它应该包含Redis集群端点和端口。

您可以在`gen-ai/inference/mistral-7b-rayserve-inf2/ray-service-mistral-ft.yaml`文件中找到启用了GCS容错的完整`RayService`配置。

使用上述`RayService`配置，我们为Ray头部Pod启用了GCS容错，Ray集群可以从头部Pod崩溃中恢复，而无需重新启动所有Ray工作节点。

让我们应用上述`RayService`配置并检查行为。

```bash
cd data-on-eks/gen-ai/inference/
envsubst < mistral-7b-rayserve-inf2/ray-service-mistral-ft.yaml| kubectl apply -f -
```
输出应该如下所示

```text
namespace/mistral created
secret/hf-token created
rayservice.ray.io/mistral created
ingress.networking.k8s.io/mistral created
```

检查集群中Ray Pod的状态。

```bash
kubectl get po -n mistral
```

Ray头部和工作节点Pod应该处于`Running`状态，如下所示。

```text
NAME                                         READY   STATUS    RESTARTS   AGE
mistral-raycluster-rf6l9-head-hc8ch          2/2     Running   0          31m
mistral-raycluster-rf6l9-worker-inf2-tdrs6   1/1     Running   0          31m
```

### 模拟Ray头部Pod崩溃

通过删除Pod来模拟Ray头部Pod崩溃

```bash
kubectl -n mistral delete po mistral-raycluster-rf6l9-head-xxxxx
pod "mistral-raycluster-rf6l9-head-xxxxx" deleted
```

我们可以看到，当Ray头部Pod终止并自动重启时，Ray工作节点Pod仍在运行。请参见Lens IDE中的以下截图。

![头部Pod删除](../../../../../../../docs/gen-ai/inference/img/head-pod-deleted.png)

![工作节点Pod不中断](../../../../../../../docs/gen-ai/inference/img/worker-pod-running.png)

#### 测试Mistral AI Gradio应用

让我们也测试我们的Gradio UI应用程序，看看在Ray头部Pod被删除时它是否能够回答问题。

通过将浏览器指向localhost:7860来打开Gradio Mistral AI聊天应用程序。

现在，通过按照上述步骤删除Ray头部Pod来重复Ray头部Pod崩溃模拟。

当Ray头部Pod终止并恢复时，将问题提交到Mistral AI聊天界面。我们可以从下面的截图中看到，聊天应用程序确实能够在Ray头部Pod被删除并恢复时提供流量。这是因为RayServe服务指向Ray工作节点Pod，在这种情况下，由于GCS容错，它从未重新启动。

![Gradio应用测试HA](../../../../../../../docs/gen-ai/inference/img/gradio-test-ft.png)

![Gradio应用测试1](../../../../../../../docs/gen-ai/inference/img/answer-1.png)

![Gradio应用测试继续](../../../../../../../docs/gen-ai/inference/img/answer-1-contd.png)

有关为RayServe应用程序启用端到端容错的完整指南，请参阅[Ray指南](https://docs.ray.io/en/latest/serve/production-guide/fault-tolerance.html#add-end-to-end-fault-tolerance)。

## 清理

最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

**步骤1：** 删除Gradio应用和mistral推理部署

```bash
cd data-on-eks/gen-ai/inference/mistral-7b-rayserve-inf2
kubectl delete -f gradio-ui.yaml
kubectl delete -f ray-service-mistral-ft.yaml
```

**步骤2：** 清理EKS集群
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/trainium-inferentia/
./cleanup.sh
```
