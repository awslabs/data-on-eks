---
sidebar_position: 1
sidebar_label: Trainium on EKS
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是由于缺少对这些资源的访问权限。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::


# Trainium on EKS
[亚马逊云科技 Trainium](https://aws.amazon.com/machine-learning/trainium/)是一种先进的ML加速器，可以改变高性能深度学习(DL)训练。由AWS Trainium芯片提供支持的`Trn1`实例专为**100B+参数**模型的高性能DL训练而构建。Trn1实例经过精心设计，具有卓越的性能，专门用于在AWS上训练流行的自然语言处理(NLP)模型，与基于GPU的EC2实例相比，可节省高达**50%的成本**。这种成本效益使其成为数据科学家和ML从业者的一个有吸引力的选择，他们寻求优化训练成本而不影响性能。

Trn1实例功能的核心是[AWS Neuron SDK](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/)，这是一个软件开发工具包，与领先的ML框架和库无缝集成，如[PyTorch](https://pytorch.org/)、[TensorFlow](https://tensorflow.org/)、[Megatron-LM](https://huggingface.co/docs/accelerate/usage_guides/megatron_lm)和[Hugging Face](https://huggingface.co/)。Neuron SDK使开发人员能够轻松地在Trainium上训练NLP、计算机视觉和推荐模型，只需要几行代码更改。

在这个蓝图中，我们将学习如何安全地部署带有Trainium节点组(`Trn1.32xlarge`和`Trn1n.32xlarge`)的[Amazon EKS集群](https://docs.aws.amazon.com/eks/latest/userguide/clusters.html)以及所有必需的插件(EC2的EFA包、Neuron设备K8s插件和EFA K8s插件)。部署完成后，我们将学习如何使用WikiCorpus数据集通过分布式PyTorch预训练训练BERT-large(双向编码器表示转换器)模型。对于分布式训练作业的调度，我们将利用[TorchX](https://pytorch.org/torchx/latest/)和[Volcano调度器](https://volcano.sh/en/)。此外，我们可以使用`neuron-top`在训练期间监控神经元活动。

#### Trianium设备架构
每个Trainium设备(芯片)包含两个神经元核心。在`Trn1.32xlarge`实例的情况下，结合了`16个Trainium设备`，总共有`32个Neuron核心`。下图提供了Neuron设备架构的可视化表示：

![Trainium设备](../../../../../../docs/blueprints/ai-ml/img/neuron-device.png)

#### AWS Neuron驱动程序
Neuron驱动程序是安装在基于AWS Inferentia的加速器(如Trainium/Inferentia实例)的主机操作系统上的一组基本软件组件。它们的主要功能是优化加速器硬件与底层操作系统之间的交互，确保无缝通信和高效利用加速器的计算能力。

#### AWS Neuron运行时
Neuron运行时由内核驱动程序和C/C++库组成，提供API来访问Inferentia和Trainium Neuron设备。用于TensorFlow、PyTorch和Apache MXNet的Neuron ML框架插件使用Neuron运行时在NeuronCores上加载和运行模型。

#### 用于Kubernetes的AWS Neuron设备插件
用于Kubernetes的AWS Neuron设备插件是一个组件，它将Trainium/Inferentia设备作为系统硬件资源在EKS集群中推广。它作为[DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)部署，确保设备插件具有适当的权限来更新节点和Pod注释，从而将Inferentia设备与Kubernetes pod无缝集成。
#### FSx for Lustre
在这个蓝图中，我们利用TorchX启动一个DataParallel BERT第一阶段预训练任务，使用64个工作节点分布在2个trn1.32xlarge（或trn1n.32xlarge）实例上，每个实例32个工作节点。BERT第一阶段预训练过程涉及一个庞大的50+ GB WikiCorpus数据集作为训练数据。为了高效处理大型数据集，将数据集包含在训练容器镜像中或在每个作业开始时下载是不切实际的。相反，我们利用共享文件系统存储，确保多个计算实例可以同时处理训练数据集。

为此，FSx for Lustre成为机器学习工作负载的理想解决方案。它提供共享文件系统存储，可以处理大规模数据集，吞吐量高达每秒数百GB，每秒数百万次IOPS，延迟低于毫秒级。我们可以动态创建FSx for Lustre并通过持久卷声明(PVC)使用FSx CSI控制器将文件系统附加到Pod上，实现共享文件存储与分布式训练过程的无缝集成。

#### TorchX
[TorchX](https://pytorch.org/torchx/main/quickstart.html) SDK或CLI提供了轻松将PyTorch作业提交到Kubernetes的功能。它提供了将预定义组件（如超参数优化、模型服务和分布式数据并行）连接到复杂管道的能力，同时利用流行的作业调度器，如Slurm、Ray、AWS Batch、Kubeflow Pipelines和Airflow。

TorchX Kubernetes调度器依赖于[Volcano调度器](https://volcano.sh/en/docs/)，必须在Kubernetes集群上安装。组调度对于多副本/多角色执行至关重要，目前，Volcano是Kubernetes内唯一满足此要求的受支持调度器。

TorchX可以与Airflow和Kubeflow Pipelines无缝集成。在这个蓝图中，我们将在本地机器/cloud9 ide上安装TorchX CLI，并使用它触发EKS集群上的作业提交，然后提交作业到在EKS集群上运行的Volcano调度器队列。

#### Volcano调度器
[Volcano调度器](https://volcano.sh/en/docs/)是一个自定义Kubernetes批处理调度器，旨在高效管理各种工作负载，特别适合资源密集型任务，如机器学习。Volcano队列作为PodGroups的集合，采用FIFO（先进先出）方法，形成资源分配的基础。VolcanoJob，也称为`vcjob`，是专为Volcano定制的自定义资源定义(CRD)对象。它与常规Kubernetes作业的不同之处在于提供高级功能，包括指定调度器、最小成员要求、任务定义、生命周期管理、特定队列分配和优先级设置。VolcanoJob特别适合高性能计算场景，如机器学习、大数据应用和科学计算。

### 解决方案架构

![架构图](../../../../../../docs/blueprints/ai-ml/img/trainium-on-eks-arch.png)


<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

:::warning
在部署此蓝图之前，重要的是要意识到与使用AWS Trainium实例相关的成本。该蓝图设置了两个`Trn1.32xlarge`实例用于预训练数据集。请确保相应地评估和规划这些成本。
:::

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/trainium)中，您将配置以下资源。

 - 创建一个新的示例VPC，包括2个私有子网和2个公共子网。
 - 为公共子网设置互联网网关，为私有子网设置NAT网关。
 - 部署带有公共端点的EKS集群控制平面（仅用于演示目的）和核心托管节点组。此外，设置两个额外的节点组：`trn1-32xl-ng1`有2个实例，`trn1n-32xl-ng`有0个实例。
 - 在trn1-32xl-ng1节点组的引导设置期间安装EFA包，并在每个实例上配置8个带有EFA的弹性网络接口(ENI)。
 - 对Trainium节点组使用EKS GPU AMI，其中包括Neuron驱动程序和运行时。
 - 部署基本附加组件，如Metrics server、Cluster Autoscaler、Karpenter、Grafana、AMP和Prometheus服务器。
 - 启用FSx for Lustre CSI驱动程序，允许为共享文件系统创建动态持久卷声明(PVC)。
 - 设置Volcano调度器用于PyTorch作业提交，允许在Kubernetes上高效任务调度。
 - 准备TorchX所需的etcd设置。
 - 在Volcano中创建测试队列，以便将TorchX作业提交到此特定队列。

:::info
**重要**：在此设置中，Karpenter专门用于`inferentia-inf2`实例，因为它目前在自定义网络接口配置方面有限制。对于Trainium实例，使用托管节点组和Cluster Autoscaler进行扩展。对于使用较旧版本Karpenter（特别是`v1alpha5` API）的用户，请注意，带有`LaunchTemplates`的Trainium配置仍然可以访问。它可以在`data-on-eks/ai-ml/trainium-inferentia/addons.tf`文件中找到，尽管在文件末尾被注释掉了。
:::

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行`install.sh`脚本

```bash
export TF_VAR_enable_fsx_for_lustre=true
export TF_VAR_enable_torchx_etcd=true
export TF_VAR_enable_volcano=true

cd data-on-eks/ai-ml/trainium-inferentia/ && chmod +x install.sh
./install.sh
```

### 验证资源

验证Amazon EKS集群

```bash
aws eks describe-cluster --name trainium-inferentia
```

```bash
# 创建k8s配置文件以与EKS进行身份验证
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia

kubectl get nodes # 输出显示EKS托管节点组节点

```

</CollapsibleContent>
### 使用AWS CloudWatch和Neuron Monitor进行可观测性

此蓝图部署CloudWatch可观测性代理作为托管附加组件，为容器化工作负载提供全面监控。它包括容器洞察，用于跟踪关键性能指标，如CPU和内存利用率。此外，该蓝图使用NVIDIA的DCGM插件集成GPU指标，这对于监控高性能GPU工作负载至关重要。对于在AWS Inferentia或Trainium上运行的机器学习模型，添加了[Neuron Monitor插件](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html#neuron-monitor-user-guide)来捕获和报告Neuron特定指标。

所有指标，包括容器洞察、GPU性能和Neuron指标，都发送到Amazon CloudWatch，您可以在那里实时监控和分析它们。部署完成后，您应该能够直接从CloudWatch控制台访问这些指标，使您能够有效地管理和优化工作负载。

### 使用TorchX和EKS在Trainium上进行分布式PyTorch训练

在此示例中，我们将使用WikiCorpus数据集对BERT-large模型执行基于DataParallel的第一阶段预训练。为了执行任务，我们将使用TorchX在两个`trn1.32xlarge`实例上启动作业，每个实例有32个工作节点。您也可以在`trn1n.32xlarge`节点组上运行相同的作业。

我们创建了三个Shell脚本，尽可能自动化作业执行。

#### 步骤1：为BERT-large模型预训练创建PyTorch Neuron容器的Docker镜像

此步骤创建一个新的Docker镜像并将其推送到ECR仓库。Dockerfile处理必要软件包的安装，如AWS Neuron仓库、Python依赖项和PyTorch和BERT预训练所需的其他基本工具。它配置各种环境变量，以确保顺利执行和最佳性能。该镜像包含关键组件，如从GitHub获取的BERT预训练脚本和requirements.txt文件，这两者对BERT预训练过程至关重要。此外，它还包括一个基本环境测试脚本用于验证目的。总之，这个Docker镜像为高效的BERT预训练与PyTorch提供了一个全面的环境，同时结合了AWS Neuron优化。

:::caution
此步骤生成一个大小为7GB或更大的AMD64 (x86-64) Docker镜像。因此，强烈建议使用安装了Docker客户端的AWS Cloud9/EC2 AMD64 (x86-64)实例，确保有足够的存储容量用于此过程。
:::

:::caution
如果您在与部署EKS集群不同的Cloud9 IDE/EC2实例上执行此脚本，必须确保使用相同的IAM角色或将其附加到Cloud9 IDE/EC2实例。如果您更喜欢为Cloud9 IDE/EC2使用不同的IAM角色，必须将其添加到EKS集群的aws-auth配置映射中，以授予该角色与EKS集群进行身份验证的授权。采取这些预防措施将使实例和EKS集群之间能够顺畅通信，确保脚本按预期运行。
:::

```bash
cd ai-ml/trainium-inferentia/examples/dp-bert-large-pretrain
chmod +x 1-bert-pretrain-build-image.sh
./1-bert-pretrain-build-image.sh
```

```
Admin:~/environment/data-on-eks/ai-ml/trainium-inferentia/examples/dp-bert-large-pretrain (trainium-part2) $ ./1-bert-pretrain-build-image.sh
Did you install docker on AMD64(x86-64) machine (y/n): y
Enter the ECR region: us-west-2
ECR repository 'eks_torchx_test' already exists.
Repository URL: <YOUR_ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/eks_torchx_test
Building and Tagging Docker image... <YOUR_ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/eks_torchx_test:bert_pretrain
[+] Building 2.4s (26/26) FINISHED
 => [internal] load build definition from Dockerfile.bert_pretrain                                                                                                                   0.0s
 => => transferring dockerfile: 5.15kB                                                                                                                                               0.0s
 => [internal] load .dockerignore                                                                                                                                                    0.0s
 => => transferring context: 2B                                                                                                                                                      0.0s
 => [internal] load metadata for docker.io/library/ubuntu:20.04                                                                                                                      0.7s
 => [ 1/22] FROM docker.io/library/ubuntu:20.04@sha256:c9820a44b950956a790c354700c1166a7ec648bc0d215fa438d3a339812f1d01                                                              0.0s
 ...
bert_pretrain: digest: sha256:1bacd5233d1a87ca1d88273c5a7cb131073c6f390f03198a91dc563158485941 size: 4729
```

登录AWS控制台并验证ECR仓库(`<YOUR_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/eks_torchx_test`)和镜像标签(`bert_pretrain`)在ECR中。

#### 步骤2：将WikiCorpus预训练数据集复制到FSx for Lustre文件系统用于BERT模型

在此步骤中，我们简化了WikiCorpus预训练数据集的传输过程，这对于由多个Trainium实例在分布式模式下训练BERT模型至关重要，将其传输到FSx for Lustre文件系统。为此，我们将登录到`cmd-shell` pod，其中包含一个AWS CLI容器，提供对文件系统的访问。

一旦进入容器，从S3存储桶(`s3://neuron-s3/training_datasets/bert_pretrain_wikicorpus_tokenized_hdf5/bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128.tar`)复制WikiCorpus数据集。然后解压数据集，使您可以访问其内容，为后续的BERT模型预训练过程做好准备。


```bash
kubectl exec -i -t -n default cmd-shell -c app -- sh -c "clear; (bash || ash || sh)"

# 登录容器后
yum install tar
cd /data
aws s3 cp s3://neuron-s3/training_datasets/bert_pretrain_wikicorpus_tokenized_hdf5/bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128.tar . --no-sign-request
chmod 744 bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128.tar
tar xvf bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128.tar
```
#### 步骤3：使用neuron_parallel_compile预编译BERT图

PyTorch Neuron引入了一个有价值的工具，称为[neuron_parallel_compile](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/frameworks/torch/torch-neuronx/api-reference-guide/training/pytorch-neuron-parallel-compile.html)，它通过提取模型图并并行编译它们，显著减少了图编译时间。这种优化技术加速了过程并导致更快的模型编译。编译后的图存储在Fsx for Lustre共享存储卷上，在模型训练期间可供工作节点访问。这种高效的方法简化了训练过程并提高了整体性能，充分利用了PyTorch Neuron的功能。

执行以下命令。此脚本提示用户配置其kubeconfig并验证`lib`文件夹中是否存在`trn1_dist_ddp.py`。它设置Docker凭证，为Kubernetes安装**TorchX**客户端。使用TorchX，脚本运行Kubernetes作业，以优化性能编译BERT图。此外，TorchX创建另一个Docker镜像并将其推送到同一仓库中的ECR仓库。此镜像用于后续的预编译pod，优化整体BERT模型训练过程。

```bash
cd ai-ml/trainium-inferentia/examples/dp-bert-large-pretrain
chmod +x 2-bert-pretrain-precompile.sh
./2-bert-pretrain-precompile.sh
```

您可以通过运行`kubectl get pods`或`kubectl get vcjob`来验证pod状态。成功的输出如下所示。

![状态图](../../../../../../docs/blueprints/ai-ml/img/pre-compile-pod-status.png)

一旦pod状态为`Succeeded`，您也可以验证其日志。预编译作业将运行约`~15分钟`。完成后，您将在输出中看到以下内容：

```
2023-07-29 09:42:42.000310: INFO ||PARALLEL_COMPILE||: Starting parallel compilations of the extracted graphs2023-07-29 09:42:42.000312: INFO ||PARALLEL_COMPILE||: Compiling /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.406_16969875447143373016.hlo.pb using following command: neuronx-cc compile —target=trn1 —framework XLA /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.406_16969875447143373016.hlo.pb —model-type=transformer —verbose=35 —output /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.406_16969875447143373016.neff
2023-07-29 09:42:42.000313: INFO ||PARALLEL_COMPILE||: Compiling /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.22250_9219523464496887986.hlo.pb using following command: neuronx-cc compile —target=trn1 —framework XLA /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.22250_9219523464496887986.hlo.pb —model-type=transformer —verbose=35 —output /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.22250_9219523464496887986.neff
2023-07-29 09:42:42.000314: INFO ||PARALLEL_COMPILE||: Compiling /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.25434_3000743782456078279.hlo.pb using following command: neuronx-cc compile —target=trn1 —framework XLA /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.25434_3000743782456078279.hlo.pb —model-type=transformer —verbose=35 —output /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.25434_3000743782456078279.neff
2023-07-29 09:42:42.000315: INFO ||PARALLEL_COMPILE||: Compiling /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.25637_13822314547392343350.hlo.pb using following command: neuronx-cc compile —target=trn1 —framework XLA /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.25637_13822314547392343350.hlo.pb —model-type=transformer —verbose=35 —output /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.25637_13822314547392343350.neff
2023-07-29 09:42:42.000316: INFO ||PARALLEL_COMPILE||: Compiling /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.21907_15179678551789598088.hlo.pb using following command: neuronx-cc compile —target=trn1 —framework XLA /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.21907_15179678551789598088.hlo.pb —model-type=transformer —verbose=35 —output /tmp/parallel_compile_workdir/MODULE_SyncTensorsGraph.21907_15179678551789598088.neff
.....
Compiler status PASS
```

新的预训练缓存文件存储在FSx for Lustre下。

![缓存](../../../../../../docs/blueprints/ai-ml/img/cache.png)


#### 步骤4：使用两个trn1.32xlarge实例的64个Neuron核心启动BERT预训练作业

我们现在进入使用WikiCorpus数据训练BERT-large模型的最后一步。

```bash
cd ai-ml/trainium-inferentia/examples/dp-bert-large-pretrain
chmod +x 3-bert-pretrain.sh
./3-bert-pretrain.sh
```

使用以下命令监控作业。这个作业可能需要几个小时，因为它正在训练30GB+的数据。

```bash
kubectl get vcjob
kubectl get pods # 默认命名空间中将有两个pod运行
```

要监控Neuron使用情况，您可以使用SSM（Systems Manager）从EC2控制台登录到其中一个Trainium EC2实例。登录后，运行命令neuron-ls，您将收到类似以下的输出。


```bash
[root@ip-100-64-229-201 aws-efa-installer]# neuron-ls
instance-type: trn1.32xlarge
instance-id: i-04b476a6a0e686980
+--------+--------+--------+---------------+---------+--------+------------------------------------------+---------+
| NEURON | NEURON | NEURON | CONNECTED | PCI | PID | COMMAND | RUNTIME |
| DEVICE | CORES | MEMORY | DEVICES | BDF | | | VERSION |
+--------+--------+--------+---------------+---------+--------+------------------------------------------+---------+
| 0 | 2 | 32 GB | 12, 3, 4, 1 | 10:1c.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 1 | 2 | 32 GB | 13, 0, 5, 2 | 10:1d.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 2 | 2 | 32 GB | 14, 1, 6, 3 | a0:1c.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 3 | 2 | 32 GB | 15, 2, 7, 0 | a0:1d.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 4 | 2 | 32 GB | 0, 7, 8, 5 | 20:1b.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 5 | 2 | 32 GB | 1, 4, 9, 6 | 20:1c.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 6 | 2 | 32 GB | 2, 5, 10, 7 | 90:1b.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 7 | 2 | 32 GB | 3, 6, 11, 4 | 90:1c.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 8 | 2 | 32 GB | 4, 11, 12, 9 | 20:1d.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 9 | 2 | 32 GB | 5, 8, 13, 10 | 20:1e.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 10 | 2 | 32 GB | 6, 9, 14, 11 | 90:1d.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 11 | 2 | 32 GB | 7, 10, 15, 8 | 90:1e.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 12 | 2 | 32 GB | 8, 15, 0, 13 | 10:1e.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 13 | 2 | 32 GB | 9, 12, 1, 14 | 10:1b.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 14 | 2 | 32 GB | 10, 13, 2, 15 | a0:1e.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
| 15 | 2 | 32 GB | 11, 14, 3, 12 | a0:1b.0 | 109459 | python3 -m torch_neuronx.distributed.... | 2.15.11 |
+--------+--------+--------+---------------+---------+--------+------------------------------------------+---------+

```

您还可以运行`neuron-top`，它提供神经元核心的实时使用情况。下图显示了所有32个神经元核心的使用情况。

![神经元顶部](../../../../../../docs/blueprints/ai-ml/img/neuron-top.png)


如果您希望终止作业，可以执行以下命令：

```bash
kubectl get vcjob # 获取作业名称
kubectl delete <输入作业名称>
```

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/trainium/ && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源
:::
