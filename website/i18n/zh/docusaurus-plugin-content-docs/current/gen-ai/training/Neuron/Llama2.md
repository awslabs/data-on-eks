---
title: Trn1上使用Nemo-Megatron的Llama-2
sidebar_position: 2
description: 使用Trainium、Neuronx-Nemo-Megatron和MPI operator训练Llama-2模型
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


# 使用Trainium、Neuronx-Nemo-Megatron和MPI operator训练Llama-2模型
欢迎阅读这份关于使用AWS Trainium、Neuronx-Nemo-Megatron和MPI operator在Amazon Elastic Kubernetes Service (EKS)上训练[Meta Llama-2-7b](https://ai.meta.com/llama/#inside-the-model)模型的综合指南。

在本教程中，您将学习如何使用Amazon EKS中的[AWS Trainium](https://aws.amazon.com/machine-learning/trainium/)加速器运行多节点训练作业。具体来说，您将使用4个AWS EC2 trn1.32xlarge实例在[RedPajama数据集的子集](https://huggingface.co/datasets/togethercomputer/RedPajama-Data-1T-Sample)上预训练Llama-2-7b。

### 什么是Llama-2？
Llama-2是一个在2万亿个文本和代码令牌上训练的大型语言模型(LLM)。它是当今可用的最大和最强大的LLM之一。Llama-2可用于各种任务，包括自然语言处理、文本生成和翻译。

虽然Llama-2作为预训练模型可用，但在本教程中，我们将展示如何从头开始预训练模型。

#### Llama-2-chat
Llama-2是一个经过严格训练过程的卓越语言模型。它首先使用公开可用的在线数据进行预训练。

Llama-2有三种不同的模型大小：

- **Llama-2-70b：** 这是最大的Llama-2模型，拥有700亿参数。它是最强大的Llama-2模型，可用于最苛刻的任务。
- **Llama-2-13b：** 这是一个中等大小的Llama-2模型，拥有130亿参数。它在性能和效率之间取得了良好的平衡，可用于各种任务。
- **Llama-2-7b：** 这是最小的Llama-2模型，拥有70亿参数。它是最高效的Llama-2模型，可用于不需要最高性能水平的任务。

### **我应该使用哪种Llama-2模型大小？**
最适合您的Llama-2模型大小将取决于您的特定需求。并且实现最高性能并不总是最大的模型。建议评估您的需求，并在选择适当的Llama-2模型大小时考虑计算资源、响应时间和成本效益等因素。决策应基于对应用程序目标和约束的全面评估。

**性能提升**
虽然Llama-2可以在GPU上实现高性能推理，但Neuron加速器将性能提升到了新的水平。Neuron加速器是专为机器学习工作负载而构建的，提供硬件加速，显著增强了Llama-2的推理速度。这转化为在Trn1/Inf2实例上部署Llama-2时更快的响应时间和改进的用户体验。
## 解决方案架构
在本节中，我们将深入探讨我们的解决方案架构。

**Trn1.32xl实例：** 这是EC2 Trn1（Trainium）实例系列的一部分，针对机器学习训练工作负载进行了优化的EC2加速实例类型

**MPI工作节点Pod：** 这些是配置为运行MPI（消息传递接口）任务的Kubernetes pod。MPI是分布式内存并行计算的标准。每个工作节点pod运行在一个trn1.32xlarge实例上，该实例配备了16个Trainium加速器和8个弹性结构适配器（EFA）。EFA是支持在Amazon EC2实例上运行的高性能计算应用程序的网络设备。

**MPI启动器Pod：** 此pod负责协调工作节点pod之间的MPI作业。当训练作业首次提交到集群时，会创建一个MPI启动器pod，它等待工作节点上线，连接到每个工作节点，并调用训练脚本。

**MPI operator：** Kubernetes中的 operator是打包、部署和管理Kubernetes应用程序的方法。MPI operator自动化了MPI工作负载的部署和管理。

**FSx for Lustre：** 一个共享的高性能文件系统，非常适合机器学习、高性能计算（HPC）、视频处理和金融建模等工作负载。FSx for Lustre文件系统将在训练作业的工作节点pod之间共享，提供一个中央存储库来访问训练数据并存储模型工件和日志。

![Llama-2-trn1](../../../../../../../docs/gen-ai/training/img/llama2-trainium.png)

## 部署解决方案

**使用AWS Trainium在Amazon EKS上训练Llama-2的步骤**

注意：本文使用Meta的Llama分词器，该分词器受用户许可保护，必须在下载分词器文件之前接受该许可。请确保您已通过在此处请求访问来获取Llama文件的访问权限。

<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
在我们开始之前，请确保您已准备好所有先决条件，以使部署过程顺利无忧。
确保您已在EC2或Cloud9实例上安装了以下工具。

* [EC2实例](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html)或[Cloud9实例](https://docs.aws.amazon.com/cloud9/latest/user-guide/tutorial-create-environment.html) → 对于两者，请确保您有100GB+的存储空间
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
* [kubectl](https://Kubernetes.io/docs/tasks/tools/)
* Git（仅适用于EC2实例）；Cloud9默认安装了git
* Docker
* [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
* Python、pip、jq、unzip

要在EC2上安装所有先决条件，您可以运行这个[脚本](https://github.com/sanjeevrg89/data-on-eks/blob/main/ai-ml/trainium-inferentia/examples/llama2/install-pre-requsites-for-ec2.sh)，它与Amazon Linux 2023兼容。


克隆Data on EKS仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到trainium-inferentia目录。

```bash
cd data-on-eks/ai-ml/trainium-inferentia
```

默认情况下**MPI operator**未安装，设置为false。我们将运行以下export命令来设置环境变量。

**注意：** 截至2024/01/04，Trainium实例仅在us-west-2、us-east-1和us-east-2区域可用。

```bash
export TF_VAR_enable_mpi_operator=true
export TF_VAR_enable_fsx_for_lustre=true
export TF_VAR_region=us-west-2
export TF_VAR_trn1_32xl_min_size=4
export TF_VAR_trn1_32xl_desired_size=4
```

运行安装脚本以配置一个带有解决方案所需的所有附加组件的EKS集群。

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
## 分布式训练
一旦EKS集群部署完成，您可以继续进行构建neuronx-nemo-megatron容器镜像并将镜像推送到ECR的下一步。

### 构建neuronx-nemo-megatron容器镜像

导航到examples/llama2目录

```bash
cd examples/llama2/
```

运行`1-llama2-neuronx-pretrain-build-image.sh`脚本来构建neuronx-nemo-megatron容器镜像并将镜像推送到ECR。

当提示输入区域时，输入您启动EKS集群的区域，如上所述。

```bash
./1-llama2-neuronx-pretrain-build-image.sh
```

注意：构建镜像并推送到ECR将花费约10分钟

### 启动并连接到CLI pod

在此步骤中，我们需要访问共享的FSx存储。要将文件复制到此存储，我们将首先启动并连接到一个运行您上面创建的neuronx-nemo-megatron docker镜像的CLI pod。

运行以下脚本来启动CLI pod：

```bash
./2-launch-cmd-shell-pod.sh
```

接下来，定期运行以下命令，直到看到CLI pod进入"Running"状态：

```bash
kubectl get pod -w
```

一旦CLI pod处于"Running"状态，使用以下命令连接到它：

```bash
kubectl exec -it cli-cmd-shell -- /bin/bash
```

### 将Llama分词器和Redpajama数据集下载到FSx

在CLI pod内，我们将下载Llama分词器文件。这些文件受Meta的Llama许可保护，因此您需要运行`huggingface-cli login`命令，使用您的访问令牌登录Hugging Face。访问令牌可在Hugging Face网站的Settings → Access Tokens下找到。

```bash
huggingface-cli login
```
当提示输入令牌时，粘贴访问令牌并按`ENTER`。

接下来，通过运行以下Python代码将llama7-7b分词器文件下载到/shared/llama7b_tokenizer：

```bash
python3 <<EOF
import transformers
tok = transformers.AutoTokenizer.from_pretrained("meta-llama/Llama-2-7b-hf")
tok.save_pretrained("/shared/llama7b_tokenizer")
EOF
```

接下来，下载RedPajama-Data-1T-Sample数据集（完整RedPajama数据集的一个小子集，包含1B令牌）。

在仍然连接到CLI pod的情况下，使用git下载数据集

```
cd /shared
git clone https://huggingface.co/datasets/togethercomputer/RedPajama-Data-1T-Sample \
    data/RedPajama-Data-1T-Sample
```

### 对数据集进行分词

使用neuronx-nemo-megatron附带的预处理脚本对数据集进行分词。这个预处理步骤在trn1.32xl实例上运行大约需要60分钟。

```bash
cd /shared

# 克隆neuronx-nemo-megatron仓库，其中包含所需的脚本
git clone https://github.com/aws-neuron/neuronx-nemo-megatron.git

# 将单独的redpajama文件合并为单个jsonl文件
cat /shared/data/RedPajama-Data-1T-Sample/*.jsonl > /shared/redpajama_sample.jsonl

# 使用llama分词器运行预处理脚本
python3 neuronx-nemo-megatron/nemo/scripts/nlp_language_modeling/preprocess_data_for_megatron.py \
    --input=/shared/redpajama_sample.jsonl \
    --json-keys=text \
    --tokenizer-library=huggingface \
    --tokenizer-type=/shared/llama7b_tokenizer \
    --dataset-impl=mmap \
    --output-prefix=/shared/data/redpajama_sample \
    --append-eod \
    --need-pad-id \
    --workers=32
```

### 修改训练脚本中的数据集和分词器路径

注意：当我们稍后在EKS中启动训练作业时，训练pod将从FSx上的neuronx-nemo-megatron/nemo/examples目录运行训练脚本。这很方便，因为它允许您直接在FSx上修改训练脚本，而无需为每次更改重新构建neuronx-nemo-megatron容器。

修改test_llama.sh脚本`/shared/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling/test_llama.sh`以更新以下两行。这些行告诉训练pod工作节点在FSx文件系统上哪里可以找到Llama分词器和数据集。

运行：
```bash
sed -i 's#^\(: ${TOKENIZER_PATH=\).*#\1/shared/llama7b_tokenizer}#' /shared/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling/test_llama.sh
sed -i 's#^\(: ${DATASET_PATH=\).*#\1/shared/data/redpajama_sample_text_document}#' /shared/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling/test_llama.sh
```

更改前：

```
: ${TOKENIZER_PATH=$HOME/llamav2_weights/7b-hf}
: ${DATASET_PATH=$HOME/examples_datasets/llama_7b/book.jsonl-processed_text_document}
```

更改后：
```
: ${TOKENIZER_PATH=/shared/llama7b_tokenizer}
: ${DATASET_PATH=/shared/data/redpajama_sample_text_document}
```

您可以通过按`CTRL-X`，然后`y`，然后`ENTER`来保存nano中的更改。

完成后，输入`exit`或按`CTRL-d`退出CLI pod。

如果您不再需要CLI pod，可以通过运行以下命令删除它：

```bash
kubectl delete pod cli-cmd-shell
```

我们终于准备好启动我们的预编译和训练作业了！

首先，让我们通过运行此命令检查MPI operator是否正常工作：

```bash
kubectl get all -n mpi-operator
```

如果MPI operator未安装，请在继续之前按照[MPI operator安装说明](https://github.com/kubeflow/mpi-operator#installation)进行操作。
在我们运行训练作业之前，我们首先运行一个预编译作业，以准备模型工件。此步骤提取并编译Llama-2-7b模型的底层计算图，并生成可以在Trainium加速器上运行的Neuron可执行文件（NEFF）。这些NEFF存储在FSx上的持久Neuron缓存中，以便训练作业稍后可以访问它们。

### 运行预编译作业

运行预编译脚本

```bash
./3-llama2-neuronx-mpi-compile.sh
```

使用4个trn1.32xlarge节点时，预编译将花费约10分钟。

定期运行`kubectl get pods | grep compile`并等待，直到看到编译作业显示"Completed"。

当预编译完成后，您可以通过运行以下脚本在4个trn1.32xl节点上启动预训练作业：

### 运行训练作业

```bash
./4-llama2-neuronx-mpi-train.sh
```

### 查看训练作业输出

要监控训练作业输出 - 首先，找到与您的训练作业关联的启动器pod的名称：

```bash
kubectl get pods | grep launcher
```

一旦您确定了启动器pod的名称并看到它处于"Running"状态，下一步是确定其UID。在以下命令中替换test-mpi-train-launcher-xxx为您的启动器pod名称，它将输出UID：

```bash
kubectl get pod test-mpi-train-launcher-xxx -o json | jq -r ".metadata.uid"
```

使用UID确定日志路径，以便您可以查看训练日志。在以下命令中用上面的值替换`UID`。

```bash
kubectl exec -it test-mpi-train-worker-0 -- tail -f /shared/nemo_experiments/UID/0/log
```

当您完成查看日志后，可以按`CTRL-C`退出tail命令。

### 监控Trainium加速器利用率

要监控Trainium加速器利用率，您可以使用neuron-top命令。Neuron-top是一个基于控制台的工具，用于监控trn1/inf2/inf1实例上的Neuron和系统相关性能指标。您可以在其中一个工作节点pod上启动neuron-top，如下所示：

```bash
kubectl exec -it test-mpi-train-worker-0 -- /bin/bash -l neuron-top
```

### 在TensorBoard中查看训练作业指标

[TensorBoard](https://www.tensorflow.org/tensorboard)是一个基于Web的可视化工具，通常用于监控和探索训练作业。它允许您快速监控训练指标，您还可以轻松比较不同训练运行之间的指标。

TensorBoard日志可在FSx for Lustre文件系统上的/shared/nemo_experiments/目录中获取。

运行以下脚本创建TensorBoard部署，以便您可以可视化Llama-2训练作业进度：

```bash
./5-deploy-tensorboard.sh
```

一旦部署准备就绪，脚本将输出一个受密码保护的URL，用于您的新TensorBoard部署。

启动URL以查看您的训练进度。

当您打开TensorBoard界面时，从左侧菜单中选择您的训练作业UID，然后从主应用程序窗口探索各种训练指标（例如：reduced-train-loss、throughput和grad-norm）。

### 停止训练作业

要停止您的训练作业并删除启动器/工作节点pod，请运行以下命令：

```bash
kubectl delete mpijob test-mpi-train
```

然后您可以运行`kubectl get pods`确认启动器/工作节点pod已被删除。

### 清理

要删除使用此解决方案创建的资源，请运行清理脚本：

```bash
cd data-on-eks/ai-ml/trainium-inferentia
./cleanup.sh
```
