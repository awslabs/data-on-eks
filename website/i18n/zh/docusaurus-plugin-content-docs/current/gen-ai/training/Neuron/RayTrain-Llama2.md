---
sidebar_position: 1
sidebar_label: 在Trn1上使用RayTrain训练Llama-2
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

注意：使用此Llama-2模型受Meta许可证的约束。
为了下载模型权重和分词器，请访问[网站](https://ai.meta.com/)并在请求访问前接受许可证。

:::

:::info

我们正在积极增强此蓝图，以纳入可观测性、日志记录和可扩展性方面的改进。

:::

# 使用RayTrain和KubeRay在Trn1上进行Llama2分布式预训练

本综合指南将引导您使用AWS Trainium (Trn1)实例和AWS Neuron SDK在Amazon EKS的KubeRay集群中预训练`Llama2-7B`语言模型。这是原始[Llama2预训练教程](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/neuronx-distributed/tutorials/training_llama2_7b.html#llama2-7b-tp-zero1-tutorial)的定制版本，针对KubeRay的分布式训练能力进行了优化。

![Llama2-RayTrain](../../../../../../../docs/gen-ai/training/img/Llama2-RayTrain-Trn1.png)

### 什么是Llama-2？

Llama-2是一个最先进的大型语言模型(LLM)，设计用于各种自然语言处理(NLP)任务，包括文本生成、摘要、翻译、问答等。它是一个强大的工具，可以针对特定用例进行微调。

### 为什么使用RayTrain和KubeRay进行分布式训练？

由于Llama-2等大型模型的广泛计算和内存需求，分布式训练至关重要。RayTrain和KubeRay的组合，特别是与AWS Trainium一起使用时，提供了一个强大的框架，可以高效有效地处理这些需求：

#### RayTrain：
- **简化的分布式训练**：RayTrain是建立在Ray框架上的高级库，抽象了分布式训练的复杂性。它允许您以最少的代码更改将Llama-2训练扩展到多个节点。Ray的基于角色的架构和基于任务的并行性使分布式工作负载能够高效执行。
- **灵活的策略**：RayTrain支持各种分布式训练策略，如数据并行和模型并行。数据并行将数据集分割到多个节点上，而模型并行则分割模型本身。这种灵活性使您能够根据模型的特定需求和训练环境的架构优化训练。
- **容错性**：RayTrain包含内置的容错机制。如果一个节点失败，Ray可以在其他可用节点上重新调度任务，确保训练作业不间断地继续。这个特性对于在大规模分布式训练环境中保持稳健性至关重要。
- **易用性**：RayTrain提供直观的API，简化了分布式训练作业的设置和执行。与流行的机器学习库（如Hugging Face Transformers）的集成使得将RayTrain纳入现有工作流程变得更加容易，无需进行广泛的修改。
#### KubeRay：
- **与Kubernetes集成**：KubeRay利用Kubernetes的原生功能来部署、管理和扩展Ray集群。这种集成允许您使用Kubernetes强大的编排功能有效地处理Ray工作负载。
- **动态扩展**：KubeRay支持Ray集群的动态扩展。Ray的内置自动缩放器可以根据工作负载需求请求额外的角色副本，而Kubernetes工具（如Karpenter或Cluster Autoscaler）管理新节点的创建以满足这些需求。
- **水平扩展**：随着计算负载的增加，通过添加更多工作节点水平扩展Ray集群。这允许高效处理大规模分布式训练和推理任务。
- **自定义资源定义(CRD)**：KubeRay利用Kubernetes CRD来定义和管理Ray集群和作业。这为在Kubernetes生态系统中处理Ray工作负载提供了一种标准化的方式。
- **容错性**：KubeRay利用Kubernetes的自我修复能力。如果Ray头节点或工作节点失败，Kubernetes会自动重启失败的组件，确保最小的停机时间和持续运行。
- **分布式调度**：Ray基于角色的模型和分布式任务调度，结合Kubernetes的编排，确保即使在节点故障的情况下也能保持高可用性和高效的任务执行。
- **声明式配置**：KubeRay允许您使用声明式YAML配置定义Ray集群和作业。这简化了部署和管理过程，使设置和维护Ray集群变得更加容易。
- **集成的日志和监控**：KubeRay与Kubernetes的日志和监控工具（如Prometheus和Grafana）集成。这提供了对Ray集群性能和健康状况的全面洞察，便于更容易地调试和优化。
- **竞价实例**：使用Kubernetes对竞价实例的支持来经济高效地运行Ray集群。这使您能够利用低成本的计算资源，同时保持根据需要进行扩展的能力。

#### AWS Trainium：
- **针对深度学习优化**：基于AWS Trainium的Trn1实例专为深度学习工作负载设计。它们提供高吞吐量和低延迟，使其成为训练Llama-2等大规模模型的理想选择。Trainium芯片相比传统处理器提供显著的性能改进，加速训练时间。
- **Neuron SDK**：AWS Neuron SDK专为优化您的深度学习模型以适应Trainium而量身定制。它包括高级编译器优化和对混合精度训练的支持等功能，可以在保持准确性的同时进一步加速您的训练工作负载。

### 为什么这种组合强大
- **简化扩展**：RayTrain和KubeRay简化了将Llama-2训练扩展到多个节点的过程。借助Ray的高效分布式执行和KubeRay的Kubernetes原生编排，您可以轻松扩展训练工作负载，充分利用Trn1实例上的AWS Trainium的全部功能。
- **优化性能**：Neuron SDK通过专门针对Trainium架构优化，增强了训练作业的性能。结合Ray高效管理分布式任务的能力和KubeRay的资源编排，这种设置确保了最佳的训练性能。
- **成本效益**：Ray的自动扩展能力和Kubernetes的资源管理帮助您通过高效分配资源并根据需求扩展集群来优化成本。这确保您只使用所需的资源，减少不必要的支出。

通过使用这种技术组合，您可以利用分布式训练和硬件方面的最新进展，高效有效地预训练Llama-2。

### 什么是Volcano？
Volcano是一个建立在Kubernetes上的开源批处理调度系统，专为管理高性能计算(HPC)和机器学习工作负载而设计。它提供了高级调度功能，如帮派调度、公平共享和抢占，这些对于在Kubernetes环境中高效运行大规模分布式训练作业至关重要。

### Volcano如何与帮派调度一起工作
Volcano的帮派调度确保作业（或"帮派"）中的所有pod同时调度。这对于分布式训练工作负载至关重要，其中多个pod需要一起启动才能正常运行。如果帮派中的任何一个pod由于资源限制而无法调度，帮派中的所有pod都不会启动。这防止了部分执行，并确保在执行开始前所有作业所需的资源都可用。

## 1. 部署解决方案
<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
    在我们开始之前，请确保您已经准备好所有先决条件，以使部署过程顺利无忧。
    确保您已在EC2或Cloud9实例上安装了以下工具。

:::info

    * [EC2实例](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html)或[Cloud9实例](https://docs.aws.amazon.com/cloud9/latest/user-guide/tutorial-create-environment.html) → 确保两种选项都有100GB+的存储空间。这对于创建具有x86架构的Docker镜像并拥有适量存储空间至关重要。

    如果您使用的是本地Windows机器或Mac，请确保本地安装了Docker，构建器存储空间超过100GB，并且镜像是使用x86架构创建的。

:::


    * [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
    * [kubectl](https://Kubernetes.io/docs/tasks/tools/)
    * [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

    要在EC2上安装所有先决条件，您可以运行这个[脚本](https://github.com/awslabs/data-on-eks/blob/main/ai-ml/trainium-inferentia/examples/llama2/install-pre-requsites-for-ec2.sh)，它与Amazon Linux 2023兼容。


    **克隆Data on EKS仓库**

    ```bash
    git clone https://github.com/awslabs/data-on-eks.git
    ```

    **导航到trainium-inferentia目录。**

    ```bash
    cd data-on-eks/ai-ml/trainium-inferentia
    ```

   让我们运行以下export命令来设置环境变量。

:::info

    **注意：** 截至2024/01/04，Trainium实例仅在us-west-2、us-east-1和us-east-2区域可用。

:::


    ```bash
    # 启用FSx for Lustre，它将预训练数据挂载到跨多个节点的所有pod
    export TF_VAR_enable_fsx_for_lustre=true

    # 根据您的要求设置区域。检查指定区域中Trn1实例的可用性。
    export TF_VAR_region=us-west-2

    # 使用KubeRay operator启用Volcano自定义调度器
    export TF_VAR_enable_volcano=true

    # 注意：此配置将创建两个新的Trn1 32xl实例。在继续之前，请确保验证相关成本。
    export TF_VAR_trn1_32xl_min_size=2
    export TF_VAR_trn1_32xl_desired_size=2
    ```

    运行安装脚本以配置具有解决方案所需的所有附加组件的EKS集群。

    ```bash
    ./install.sh
    ```

    ### 验证资源

    验证Amazon EKS集群

    ```bash
    aws eks --region us-west-2 describe-cluster --name trainium-inferentia
    ```

    ```bash
    # 创建k8s配置文件以与EKS进行身份验证
    aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia

    kubectl get nodes # 输出显示EKS托管节点组节点
    ```

</CollapsibleContent>

## 2. 构建Docker镜像（可选步骤）

为了简化蓝图部署，我们已经构建了Docker镜像并在公共ECR下提供。
如果您想自定义Docker镜像，可以更新`Dockerfile`并按照可选步骤构建Docker镜像。
请注意，您还需要使用您自己的私有ECR中新创建的镜像修改RayCluster YAML文件`llama2-pretrain-trn1-raycluster.yaml`。

```bash
cd gen-ai/training/raytrain-llama2-pretrain-trn1
./kuberay-trn1-llama2-pretrain-build-image.sh
```
运行此脚本后，记下生成的Docker镜像URL和标签。
您将在下一步中需要这些信息。

## 3. 使用KubeRay operator启动Ray集群

如果您跳过步骤2，则无需修改YAML文件。
您可以简单地对文件运行`kubectl apply`命令，它将使用我们发布的公共ECR镜像。

如果您在**步骤2**中构建了自定义Docker镜像，请使用从上一步获得的Docker镜像URL和标签更新`gen-ai/training/raytrain-llama2-pretrain-trn1/llama2-pretrain-trn1-raycluster.yaml`文件。

一旦您更新了YAML文件（如果需要），运行以下命令在您的EKS集群中启动KubeRay集群pod：

```bash
kubectl apply -f llama2-pretrain-trn1-raycluster.yaml
```

**验证Pod状态：**

```bash
kubectl get pods -l "ray.io/cluster=kuberay-trn1"
```
### 使用Volcano进行Ray头部和工作节点Pod的帮派调度

在部署用于训练Llama2的Ray集群的上下文中，Volcano对于确保Ray头部和工作节点pod一起高效调度至关重要。
Ray头部pod，通常运行在x86实例上，协调分布式训练，而工作节点pod，运行在AWS Trainium (Trn1)实例上，执行计算密集型任务。
通过利用**Volcano的帮派调度**，我们可以确保头部和所有工作节点pod同时分配必要的资源，使分布式训练作业能够无延迟地启动。

以下是将Volcano与用于Llama2训练的RayCluster集成的配置示例：

:::info

我们在此部署中使用默认命名空间，因为`fsx-claim` **PVC**是由Terraform蓝图在`default`命名空间下创建的。

如果您想在专用命名空间中部署集群，请确保FSX for Lustre文件系统也在同一命名空间中创建，因为PVC是命名空间绑定的。

:::

```yaml
# Volcano与KubeRay的文档：https://docs.ray.io/en/master/cluster/kubernetes/k8s-ecosystem/volcano.html
---
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: llama2-training-queue
  namespace: default
spec:
  weight: 1
  capability:
    cpu: '500'
    memory: 1500Gi

---
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: kuberay-trn1
  namespace: default
  labels:
    ray.io/scheduler-name: volcano
    volcano.sh/queue-name: llama2-training-queue
spec:
  rayVersion: 2.22.0
  headGroupSpec:
...
...
```

您应该看到一个ray-head pod和两个ray-worker pod处于Running状态：

:::warning

请注意，镜像拉取和pod准备就绪可能需要长达10分钟的时间。

:::

```bash
NAME                                    READY   STATUS    RESTARTS   AGE
kuberay-trn1-head-67t46                 0/1     Pending   0          2m50s
kuberay-trn1-worker-workergroup-fz8bs   0/1     Pending   0          2m50s
kuberay-trn1-worker-workergroup-gpnxh   0/1     Pending   0          2m50s
```

检查头部pod的日志：

查找表明Ray头部已启动且集群正在运行的消息。

```bash
kubectl logs kuberay-trn1-head-xxxxx
```

### 访问Ray仪表板（端口转发）：
Ray仪表板提供了关于集群状态和作业进度的宝贵洞察。要访问它：

**转发端口：**

这将从您的本地机器到集群内的头部pod转发Ray仪表板端口(8265)。

```bash
kubectl port-forward service/kuberay-trn1-head-svc 8265:8265
```

打开浏览器并在您的网络浏览器中导航到[http://localhost:8265](http://localhost:8265)以查看仪表板。


## 4. 在FSx共享文件系统上生成预训练数据

:::warning

数据生成步骤可能需要长达20分钟的时间，以在FSx for Lustre中创建所有数据。

:::


在此步骤中，我们将利用KubeRay的作业规范来启动数据生成过程。我们将直接向Ray头部pod提交作业。这个作业在为您的模型准备训练方面起着关键作用。

查看下面的`RayJob`定义规范，使用`clusterSelector`利用现有RayCluster向RayCluster提交作业。

```yaml
# ----------------------------------------------------------------------------
# RayJob: llama2-generate-pretraining-test-data
#
# 描述：
# 此RayJob负责生成Llama2模型训练所需的预训练测试数据。它从指定的数据集获取数据，
# 处理它，并准备用于后续训练阶段。该作业运行一个Python脚本（`get_dataset.py`），
# 执行这些数据准备步骤。

# 用法：
# 使用`kubectl apply -f 1-llama2-pretrain-trn1-rayjob-create-test-data.yaml`将此配置应用到您的Kubernetes集群。
# 确保Ray集群（`kuberay-trn1`）在指定的命名空间中运行并可访问。
# ----------------------------------------------------------------------------

apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: llama2-generate-pretraining-test-data
  namespace: default
spec:
  submissionMode: K8sJobMode
  entrypoint: "python3 get_dataset.py"
  runtimeEnvYAML: |
    working_dir: /llama2_pretrain
    env_vars:
      PYTHONUNBUFFERED: '0'
    resources:
      requests:
        cpu: "6"
        memory: "30Gi"
  clusterSelector:
    ray.io/cluster: kuberay-trn1
    rayClusterNamespace: default  # 替换为您的RayCluster部署的命名空间
  ttlSecondsAfterFinished: 60  # 完成后pod的生存时间（秒）
```

执行以下命令运行测试数据创建Ray作业：


```bash
kubectl apply -f 1-llama2-pretrain-trn1-rayjob-create-test-data.yaml
```

**幕后发生的事情：**

**作业启动：** 您将使用kubectl提交KubeRay作业规范。您的`kuberay-trn1`集群中的Ray头部pod接收并执行此作业。

**数据生成：** 该作业运行`gen-ai/training/raytrain-llama2-pretrain-trn1/llama2_pretrain/get_dataset.py`脚本，该脚本利用Hugging Face数据集库的强大功能来获取和处理原始英语维基百科数据集（"wikicorpus"）。

**分词：** 该脚本使用来自Hugging Face transformers的预训练分词器对文本进行分词。分词将文本分解为更小的单元（单词或子词），以便模型理解。

**数据存储：** 分词后的数据被整齐地组织并保存到FSx for Lustre共享文件系统内的特定目录（`/shared/wikicorpus_llama2_7B_tokenized_4k/`）。这确保集群中的所有工作节点在预训练期间都可以轻松访问这些标准化数据。

### 监控作业：

要跟踪作业的进度：

**Ray仪表板**：前往Ray仪表板，可通过Ray头部pod的IP地址和端口8265访问。您将看到关于作业状态的实时更新。


![准备数据集](../../../../../../../docs/gen-ai/training/img/raytrain-testdata-raydash1.png)

![准备数据集](../../../../../../../docs/gen-ai/training/img/raytrain-testdata-raydash2.png)

![准备数据集](../../../../../../../docs/gen-ai/training/img/raytrain-testdata-raydash3.png)

或者，您可以在终端中使用以下命令：

```bash
kubectl get pods | grep llama2
```

**输出：**

```
llama2-generate-pretraining-test-data-g6ccl   1/1     Running   0             5m5s
```

以下截图来自Lens K8s IDE，显示了pod的日志。

![准备数据集](../../../../../../../docs/gen-ai/training/img/raytrain-testdata-lens.png)

## 5. 运行预编译作业（优化步骤）

:::info

预编译作业可能需要长达6分钟

:::

在开始实际训练之前，我们将执行预编译步骤，以优化模型以适应Neuron SDK。这有助于模型在`Trn1`实例上更高效地运行。此脚本将使用Neuron SDK编译和优化模型的计算图，使其准备好在Trn1处理器上进行高效训练。

在此步骤中，您将运行一个预编译作业，其中Neuron SDK将识别、编译和缓存与`Llama2`预训练相关的计算图。

查看下面的`RayJob`定义规范，以运行预编译作业：
```yaml
# ----------------------------------------------------------------------------
# RayJob: llama2-precompilation-job
#
# 描述：
# 此RayJob负责Llama2模型训练所需的预编译步骤。它运行一个Python脚本（`ray_train_llama2.py`），
# 带有`--neuron_parallel_compile`选项，使用AWS Neuron设备并行编译模型。这一步对于
# 优化模型以在AWS基础设施上进行高效训练至关重要。

# 用法：
# 使用`kubectl apply -f 2-llama2-pretrain-trn1-rayjob-precompilation.yaml`将此配置应用到您的Kubernetes集群。
# 确保Ray集群（`kuberay-trn1`）在指定的命名空间中运行并可访问。
# ----------------------------------------------------------------------------

---
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: llama2-precompilation-job
  namespace: default
spec:
  submissionMode: K8sJobMode
  entrypoint: "NEURON_NUM_DEVICES=32 python3 /llama2_pretrain/ray_train_llama2.py --neuron_parallel_compile"
  runtimeEnvYAML: |
    working_dir: /llama2_pretrain
    env_vars:
      PYTHONUNBUFFERED: '0'
  clusterSelector:
    ray.io/cluster: kuberay-trn1
    rayClusterNamespace: default  # 替换为您的RayCluster部署的命名空间
  ttlSecondsAfterFinished: 60  # 完成后pod的生存时间（秒）
```

执行以下命令运行预编译作业：

```bash
kubectl apply -f 2-llama2-pretrain-trn1-rayjob-precompilation.yaml
```

**验证步骤：**

要监控作业的进度并验证其是否正确运行，请使用以下命令和工具：

**Ray仪表板：** 通过Ray头部pod的IP地址和端口`8265`访问Ray仪表板，查看关于作业状态的实时更新。

![预编译进度](../../../../../../../docs/gen-ai/training/img/raytrain-precomplilation1.png)

![预编译进度](../../../../../../../docs/gen-ai/training/img/raytrain-precomplilation2.png)

以下截图来自Lens K8s IDE，显示了pod的日志。

![预编译进度](../../../../../../../docs/gen-ai/training/img/raytrain-precomplilation3.png)

## 6. 运行分布式预训练作业

:::warning

此作业可能运行数小时，因此一旦您确信损失正在减少且模型正在学习，可以随时使用Ctrl+C取消作业。

:::

现在，您已准备好开始实际训练Llama 2模型！此步骤涉及使用RayJob运行分布式预训练作业。该作业将利用AWS Neuron设备高效地使用准备好的数据集训练模型。

查看下面的`RayJob`定义规范，以运行预训练作业：

```yaml
# ----------------------------------------------------------------------------
# RayJob: llama2-pretraining-job
#
# 描述：
# 此RayJob负责Llama2模型的主要预训练步骤。
# 它运行一个Python脚本（`ray_train_llama2.py`）使用AWS Neuron设备执行预训练。
# 这一步对于使用准备好的数据集训练语言模型至关重要。

# 用法：
# 使用`kubectl apply -f 3-llama2-pretrain-trn1-rayjob.yaml`将此配置应用到您的Kubernetes集群。
# 确保Ray集群（`kuberay-trn1`）在指定的命名空间中运行并可访问。
# ----------------------------------------------------------------------------

---
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: llama2-pretraining-job
  namespace: default
spec:
  submissionMode: K8sJobMode
  entrypoint: "NEURON_NUM_DEVICES=32 python3 ray_train_llama2.py"
  runtimeEnvYAML: |
    working_dir: /llama2_pretrain
    env_vars:
      PYTHONUNBUFFERED: '0'
  clusterSelector:
    ray.io/cluster: kuberay-trn1
    rayClusterNamespace: default  # 替换为您的RayCluster部署的命名空间
  shutdownAfterJobFinishes: true
  activeDeadlineSeconds: 600   # 如果作业运行时间超过600秒（10分钟），将被终止
  ttlSecondsAfterFinished: 60  # 完成后pod的生存时间（秒）
```
执行以下命令运行预训练作业：

```bash
kubectl apply -f 3-llama2-pretrain-trn1-rayjob.yaml
```

**监控进度：**

您可以使用Ray仪表板或通过观察输出到终端的日志来监控训练作业的进度。查找诸如训练损失、学习率和其他指标等信息，以评估模型学习的情况。

![训练进度](../../../../../../../docs/gen-ai/training/img/raytrain-training-progress1.png)

**Ray仪表板：** 通过Ray头部pod的IP地址和端口8265访问Ray仪表板，查看关于作业状态的实时更新。

![Ray仪表板训练进度](../../../../../../../docs/gen-ai/training/img/raytrain-training-progress2.png)

![Ray仪表板训练进度](../../../../../../../docs/gen-ai/training/img/raytrain-training-progress3.png)


### 清理

要删除使用此解决方案创建的资源，请运行清理脚本：

```bash
# 删除RayCluster资源：
cd gen-ai/training/raytrain-llama2-pretrain-trn1
kubectl delete -f llama2-pretrain-trn1-raycluster.yaml

# 清理EKS集群和相关资源：
cd data-on-eks/ai-ml/trainium-inferentia
./cleanup.sh
```
