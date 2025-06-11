---
sidebar_position: 1
sidebar_label: EKS上的BioNeMo
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

# EKS上的BioNeMo

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::caution
此蓝图应被视为实验性的，仅应用于概念验证。
:::


## 简介

[NVIDIA BioNeMo](https://www.nvidia.com/en-us/clara/bionemo/)是一个用于药物发现的生成式AI平台，它简化并加速了使用您自己的数据训练模型以及扩展模型部署用于药物发现应用的过程。BioNeMo提供了AI模型开发和部署的最快路径，加速了AI驱动的药物发现之旅。它拥有不断增长的用户和贡献者社区，并由NVIDIA积极维护和开发。

鉴于其容器化特性，BioNeMo在各种环境中部署时具有多样性，如Amazon Sagemaker、AWS ParallelCluster、Amazon ECS和Amazon EKS。然而，此解决方案专注于在Amazon EKS上特定部署BioNeMo。

*来源：https://blogs.nvidia.com/blog/bionemo-on-aws-generative-ai-drug-discovery/*

## 在Kubernetes上部署BioNeMo

此蓝图利用三个主要组件实现其功能。NVIDIA设备插件促进GPU使用，FSx存储训练数据，Kubeflow训练操作符管理实际的训练过程。

1) [**Kubeflow训练操作符**](https://www.kubeflow.org/docs/components/training/)
2) [**NVIDIA设备插件**](https://github.com/NVIDIA/k8s-device-plugin)
3) [**FSx for Lustre CSI驱动程序**](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html)


在此蓝图中，我们将部署Amazon EKS集群并执行数据准备作业和分布式模型训练作业。
<CollapsibleContent header={<h3><span>先决条件</span></h3>}>

确保您已在本地机器或用于部署Terraform蓝图的机器（如Mac、Windows或Cloud9 IDE）上安装了以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

</CollapsibleContent>

<CollapsibleContent header={<h3><span>部署蓝图</span></h3>}>

#### 克隆仓库

首先，克隆包含部署蓝图所需文件的仓库。在终端中使用以下命令：

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

#### 初始化Terraform

导航到您想要部署的蓝图特定目录。在这种情况下，我们对BioNeMo蓝图感兴趣，因此使用终端导航到适当的目录：

```bash
cd data-on-eks/ai-ml/bionemo
```

#### 运行安装脚本

使用提供的辅助脚本`install.sh`运行terraform init和apply命令。默认情况下，脚本将EKS集群部署到`us-west-2`区域。更新`variables.tf`以更改区域。这也是更新任何其他输入变量或对terraform模板进行任何其他更改的时机。


```bash
./install .sh
```

更新本地kubeconfig，以便我们可以访问kubernetes集群

```bash
aws eks update-kubeconfig --name bionemo-on-eks #或者您用于EKS集群名称的任何名称
```

由于训练操作符没有helm图表，我们必须手动安装该包。如果训练操作符团队构建了helm图表，我们
将把它纳入terraform-aws-eks-data-addons仓库。

#### 安装Kubeflow训练操作符
```bash
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"
```

</CollapsibleContent>

<CollapsibleContent header={<h3><span>验证部署</span></h3>}>

首先，让我们验证集群中有工作节点在运行。

```bash
kubectl get nodes
```
```bash
NAME                                           STATUS   ROLES    AGE   VERSION
ip-100-64-180-114.us-west-2.compute.internal   Ready    <none>   17m   v1.29.0-eks-5e0fdde
ip-100-64-19-70.us-west-2.compute.internal     Ready    <none>   16m   v1.29.0-eks-5e0fdde
ip-100-64-205-93.us-west-2.compute.internal    Ready    <none>   17m   v1.29.0-eks-5e0fdde
ip-100-64-235-15.us-west-2.compute.internal    Ready    <none>   16m   v1.29.0-eks-5e0fdde
ip-100-64-34-75.us-west-2.compute.internal     Ready    <none>   17m   v1.29.0-eks-5e0fdde
...
```

接下来，让我们验证所有pod都在运行。

```bash
kubectl get pods -A
```

```bash
NAMESPACE              NAME                                                              READY   STATUS    RESTARTS   AGE
amazon-cloudwatch      aws-cloudwatch-metrics-4g9dm                                      1/1     Running   0          15m
amazon-cloudwatch      aws-cloudwatch-metrics-4ktjc                                      1/1     Running   0          15m
amazon-cloudwatch      aws-cloudwatch-metrics-5hj96                                      1/1     Running   0          15m
amazon-cloudwatch      aws-cloudwatch-metrics-k84p5                                      1/1     Running   0          15m
amazon-cloudwatch      aws-cloudwatch-metrics-rkt8f                                      1/1     Running   0          15m
kube-system            aws-node-4pnpr                                                    2/2     Running   0          15m
kube-system            aws-node-jrksf                                                    2/2     Running   0          15m
kube-system            aws-node-lv7vn                                                    2/2     Running   0          15m
kube-system            aws-node-q7cp9                                                    2/2     Running   0          14m
kube-system            aws-node-zplq5                                                    2/2     Running   0          14m
kube-system            coredns-86bd649884-8kwn9                                          1/1     Running   0          15m
kube-system            coredns-86bd649884-bvltg                                          1/1     Running   0          15m
kube-system            fsx-csi-controller-85d9ddfbff-7hgmn                               4/4     Running   0          16m
kube-system            fsx-csi-controller-85d9ddfbff-lp28p                               4/4     Running   0          16m
kube-system            fsx-csi-node-2tfgq                                                3/3     Running   0          16m
kube-system            fsx-csi-node-jtdd6                                                3/3     Running   0          16m
kube-system            fsx-csi-node-kj6tz                                                3/3     Running   0          16m
kube-system            fsx-csi-node-pwp5x                                                3/3     Running   0          16m
kube-system            fsx-csi-node-rl59r                                                3/3     Running   0          16m
kube-system            kube-proxy-5nbms                                                  1/1     Running   0          15m
kube-system            kube-proxy-dzjxz                                                  1/1     Running   0          15m
kube-system            kube-proxy-j9bnp                                                  1/1     Running   0          15m
kube-system            kube-proxy-p8xwq                                                  1/1     Running   0          15m
kube-system            kube-proxy-pgqbb                                                  1/1     Running   0          15m
kubeflow               training-operator-64c768746c-l5fbq                                1/1     Running   0          24s
nvidia-device-plugin   neuron-device-plugin-gpu-feature-discovery-g4xx9                  1/1     Running   0          15m
nvidia-device-plugin   neuron-device-plugin-gpu-feature-discovery-ggwjm                  1/1     Running   0          15m
nvidia-device-plugin   neuron-device-plugin-node-feature-discovery-master-68bc46c9dbw8   1/1     Running   0          16m
nvidia-device-plugin   neuron-device-plugin-node-feature-discovery-worker-6b94s          1/1     Running   0          16m
nvidia-device-plugin   neuron-device-plugin-node-feature-discovery-worker-7jzsn          1/1     Running   0          16m
nvidia-device-plugin   neuron-device-plugin-node-feature-discovery-worker-kt9fd          1/1     Running   0          16m
nvidia-device-plugin   neuron-device-plugin-node-feature-discovery-worker-vlpdp          1/1     Running   0          16m
nvidia-device-plugin   neuron-device-plugin-node-feature-discovery-worker-wwnk6          1/1     Running   0          16m
nvidia-device-plugin   neuron-device-plugin-nvidia-device-plugin-mslxx                   1/1     Running   0          15m
nvidia-device-plugin   neuron-device-plugin-nvidia-device-plugin-phw2j                   1/1     Running   0          15m
...
```
:::info
确保training-operator、nvidia-device-plugin和fsx-csi-controller pod正在运行且健康。

:::
</CollapsibleContent>

### 运行BioNeMo训练作业

一旦您确保所有组件都正常运行，您可以继续向集群提交作业。

#### 步骤1：启动Uniref50数据准备任务

第一个任务，名为`uniref50-job.yaml`，涉及下载和分区数据以提高处理效率。此任务专门检索`uniref50数据集`并将其组织在FSx for Lustre文件系统内。这种结构化布局是为了训练、测试和验证目的而设计的。您可以在[这里](https://www.uniprot.org/help/uniref)了解更多关于uniref数据集的信息。

要执行此作业，导航到`examples\training`目录并使用以下命令部署`uniref50-job.yaml`清单：

```bash
cd examples/training
kubectl apply -f uniref50-job.yaml
```

:::info

重要的是要注意，此任务需要大量时间，通常在50到60小时之间。

:::

运行以下命令查找pod `uniref50-download-*`

```bash
kubectl get pods
```

要验证其进度，请检查相应pod生成的日志：

```bash
kubectl logs uniref50-download-xnz42

[NeMo I 2024-02-26 23:02:20 preprocess:289] Download and preprocess of UniRef50 data does not currently use GPU. Workstation or CPU-only instance recommended.
[NeMo I 2024-02-26 23:02:20 preprocess:115] Data processing can take an hour or more depending on system resources.
[NeMo I 2024-02-26 23:02:20 preprocess:117] Downloading file from https://ftp.uniprot.org/pub/databases/uniprot/uniref/uniref50/uniref50.fasta.gz...
[NeMo I 2024-02-26 23:02:20 preprocess:75] Downloading file to /fsx/raw/uniref50.fasta.gz...
[NeMo I 2024-02-26 23:08:33 preprocess:89] Extracting file to /fsx/raw/uniref50.fasta...
[NeMo I 2024-02-26 23:12:46 preprocess:311] UniRef50 data processing complete.
[NeMo I 2024-02-26 23:12:46 preprocess:313] Indexing UniRef50 dataset.
[NeMo I 2024-02-26 23:16:21 preprocess:319] Writing processed dataset files to /fsx/processed...
[NeMo I 2024-02-26 23:16:21 preprocess:255] Creating train split...
```


完成此任务后，处理后的数据集将保存在`/fsx/processed`目录中。完成后，我们可以继续并通过运行以下命令启动`预训练`作业：

接下来，我们可以通过运行以下命令执行预训练作业：

在这个PyTorchJob YAML中，命令`python3 -m torch.distributed.run`在您的Kubernetes集群中跨多个工作节点pod编排**分布式训练**方面起着至关重要的作用。

它处理以下任务：

1. 初始化分布式后端（例如，c10d，NCCL）用于工作进程之间的通信。在我们的示例中，它使用的是c10d。这是PyTorch中常用的分布式后端，可以根据您的环境利用不同的通信机制，如TCP或Infiniband。
2. 设置环境变量以在您的训练脚本中启用分布式训练。
3. 在所有工作节点pod上启动您的训练脚本，确保每个进程参与分布式训练。


```bash
cd examples/training
kubectl apply -f esm1nv_pretrain-job.yaml
```

运行以下命令查找pod `esm1nv-pretraining-worker-*`

```bash
kubectl get pods
```
```bash
NAME                           READY   STATUS    RESTARTS   AGE
esm1nv-pretraining-worker-0    1/1     Running   0          13m
esm1nv-pretraining-worker-1    1/1     Running   0          13m
esm1nv-pretraining-worker-10   1/1     Running   0          13m
esm1nv-pretraining-worker-11   1/1     Running   0          13m
esm1nv-pretraining-worker-12   1/1     Running   0          13m
esm1nv-pretraining-worker-13   1/1     Running   0          13m
esm1nv-pretraining-worker-14   1/1     Running   0          13m
esm1nv-pretraining-worker-15   1/1     Running   0          13m
esm1nv-pretraining-worker-2    1/1     Running   0          13m
esm1nv-pretraining-worker-3    1/1     Running   0          13m
esm1nv-pretraining-worker-4    1/1     Running   0          13m
esm1nv-pretraining-worker-5    1/1     Running   0          13m
esm1nv-pretraining-worker-6    1/1     Running   0          13m
esm1nv-pretraining-worker-7    1/1     Running   0          13m
esm1nv-pretraining-worker-8    1/1     Running   0          13m
esm1nv-pretraining-worker-9    1/1     Running   0          13m
```

我们应该看到16个pod在运行。我们选择了p3.16xlarge实例，每个实例有8个GPU。在pod定义中，我们指定每个作业将利用1个gpu。
由于我们将"nprocPerNode"设置为"8"，每个节点将负责8个作业。由于我们有2个节点，总共将启动16个pod。有关分布式pytorch训练的更多详情，请参见[pytorch文档](https://pytorch.org/docs/stable/distributed.html)。

:::info
这个训练作业使用2个p3.16xlarge节点至少需要运行3-4天。
:::

此配置利用了Kubeflow的PyTorch训练自定义资源定义(CRD)。在此清单中，各种参数可供自定义。有关每个参数的详细见解和微调指导，您可以参考[BioNeMo的文档](https://docs.nvidia.com/bionemo-framework/latest/notebooks/model_training_esm1nv.html)。

:::info
根据Kubeflow训练操作符文档，如果您没有明确指定主副本pod，第一个工作副本pod(worker-0)将被视为主pod。
:::

要跟踪此过程的进度，请按照以下步骤操作：

```bash
kubectl logs esm1nv-pretraining-worker-0

Epoch 0:   7%|▋         | 73017/1017679 [00:38<08:12, 1918.0%
```

此外，要监控GPU的使用情况，您可以选择通过EC2控制台使用Session Manager连接到您的节点并运行`nvidia-smi`命令。如果您想要更强大的可观测性，可以参考[DCGM Exporter](https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/latest/dcgm-exporter.html)。


```bash
sh-4.2$ nvidia-smi
Thu Mar  7 16:31:01 2024
+---------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.129.03             Driver Version: 535.129.03   CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  Tesla V100-SXM2-16GB           On  | 00000000:00:17.0 Off |                    0 |
| N/A   51C    P0              80W / 300W |   3087MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   1  Tesla V100-SXM2-16GB           On  | 00000000:00:18.0 Off |                    0 |
| N/A   44C    P0              76W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   2  Tesla V100-SXM2-16GB           On  | 00000000:00:19.0 Off |                    0 |
| N/A   43C    P0              77W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   3  Tesla V100-SXM2-16GB           On  | 00000000:00:1A.0 Off |                    0 |
| N/A   52C    P0              77W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   4  Tesla V100-SXM2-16GB           On  | 00000000:00:1B.0 Off |                    0 |
| N/A   49C    P0              79W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   5  Tesla V100-SXM2-16GB           On  | 00000000:00:1C.0 Off |                    0 |
| N/A   44C    P0              74W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   6  Tesla V100-SXM2-16GB           On  | 00000000:00:1D.0 Off |                    0 |
| N/A   44C    P0              78W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   7  Tesla V100-SXM2-16GB           On  | 00000000:00:1E.0 Off |                    0 |
| N/A   50C    P0              79W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+

+---------------------------------------------------------------------------------------+
| Processes:                                                                            |
|  GPU   GI   CI        PID   Type   Process name                            GPU Memory |
|        ID   ID                                                             Usage      |
|=======================================================================================|
|    0   N/A  N/A   1552275      C   /usr/bin/python3                           3084MiB |
|    1   N/A  N/A   1552277      C   /usr/bin/python3                           3082MiB |
|    2   N/A  N/A   1552278      C   /usr/bin/python3                           3082MiB |
|    3   N/A  N/A   1552280      C   /usr/bin/python3                           3082MiB |
|    4   N/A  N/A   1552279      C   /usr/bin/python3                           3082MiB |
|    5   N/A  N/A   1552274      C   /usr/bin/python3                           3082MiB |
|    6   N/A  N/A   1552273      C   /usr/bin/python3                           3082MiB |
|    7   N/A  N/A   1552276      C   /usr/bin/python3                           3082MiB |
+---------------------------------------------------------------------------------------+
```
#### 分布式训练的好处：

通过在工作节点pod的多个GPU上分配训练工作负载，您可以利用所有GPU的组合计算能力更快地训练大型模型。处理可能无法适应单个GPU内存的更大数据集。

#### 结论
BioNeMo作为一种专为药物发现领域量身定制的强大生成式AI工具而存在。在这个说明性示例中，我们采取主动，利用广泛的uniref50数据集从头开始预训练自定义模型。然而，值得注意的是，BioNeMo提供了通过直接使用[NVidia提供的](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/clara/containers/bionemo-framework)预训练模型来加速过程的灵活性。这种替代方法可以显著简化您的工作流程，同时保持BioNeMo框架的强大功能。


<CollapsibleContent header={<h3><span>清理</span></h3>}>

使用提供的辅助脚本`cleanup.sh`拆除EKS集群和其他AWS资源。

```bash
cd ../../
./cleanup.sh
```

</CollapsibleContent>
