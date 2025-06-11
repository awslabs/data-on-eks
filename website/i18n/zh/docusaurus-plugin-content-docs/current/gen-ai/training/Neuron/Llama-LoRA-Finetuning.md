---
sidebar_position: 1
sidebar_label: 在Trn1上使用RayTrain训练Llama-3
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::danger

注意：使用此Llama-3模型受Meta许可证的约束。
为了下载模型权重和分词器，请访问[网站](https://ai.meta.com/)并在请求访问前接受许可证。

:::

:::info

我们正在积极增强此蓝图，以纳入可观测性、日志记录和可扩展性方面的改进。

:::

# 使用HuggingFace Optimum Neuron在Trn1上微调Llama3

本综合指南将引导您使用AWS Trainium (Trn1) EC2实例微调`Llama3-8B`语言模型的步骤。微调过程由HuggingFace Optimum Neuron促进，这是一个强大的库，简化了将Neuron集成到您的训练管道中。

### 什么是Llama-3？

Llama-3是一个最先进的大型语言模型(LLM)，设计用于各种自然语言处理(NLP)任务，包括文本生成、摘要、翻译、问答等。它是一个强大的工具，可以针对特定用例进行微调。

#### AWS Trainium：
- **针对深度学习优化**：基于AWS Trainium的Trn1实例专为深度学习工作负载设计。它们提供高吞吐量和低延迟，使其成为训练Llama-3等大规模模型的理想选择。Trainium芯片相比传统处理器提供显著的性能改进，加速训练时间。
- **Neuron SDK**：AWS Neuron SDK专为优化您的深度学习模型以适应Trainium而量身定制。它包括高级编译器优化和对混合精度训练的支持等功能，可以在保持准确性的同时进一步加速您的训练工作负载。

## 1. 部署解决方案
<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
    在我们开始之前，请确保您已经准备好所有先决条件，以使部署过程顺利无忧。
    确保您已在EC2实例上安装了以下工具。

:::info

    * [EC2实例](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html) → 确保您有100GB+的存储空间。这对于创建具有x86架构的Docker镜像并拥有适量存储空间至关重要。

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

    **注意：** Trainium实例在特定区域可用，用户可以使用[这里](https://repost.aws/articles/ARmXIF-XS3RO27p0Pd1dVZXQ/what-regions-have-aws-inferentia-and-trainium-instances)re:Post上概述的命令确定这些区域的列表。

:::


    ```bash
    # 启用FSx for Lustre，它将预训练数据挂载到跨多个节点的所有pod
    export TF_VAR_enable_fsx_for_lustre=true

    # 根据您的要求设置区域。检查指定区域中Trn1实例的可用性。
    export TF_VAR_region=us-west-2

    # 注意：此配置将创建两个新的Trn1 32xl实例。在继续之前，请确保验证相关成本。
    export TF_VAR_trn1_32xl_min_size=1
    export TF_VAR_trn1_32xl_desired_size=1
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

为了简化蓝图部署，我们已经构建了Docker镜像并在公共ECR下提供。如果您想自定义Docker镜像，可以更新`Dockerfile`并按照可选步骤构建Docker镜像。请注意，您还需要使用您自己的私有ECR中新创建的镜像修改YAML文件`lora-finetune-pod.yaml`。

确保您位于data-on-eks仓库的根文件夹后，执行以下命令。

```bash
cd gen-ai/training/llama-lora-finetuning-trn1
./build-container-image.sh
```
运行此脚本后，记下生成的Docker镜像URL和标签。
您将在下一步中需要这些信息。

## 3. 启动Llama训练pod

如果您跳过步骤2，则无需修改YAML文件。
您可以简单地对文件运行`kubectl apply`命令，它将使用我们发布的公共ECR镜像。

如果您在**步骤2**中构建了自定义Docker镜像，请使用从上一步获得的Docker镜像URL和标签更新`gen-ai/training/llama-lora-finetuning-trn1/lora-finetune-pod.yaml`文件。

一旦您更新了YAML文件（如果需要），运行以下命令在您的EKS集群中启动pod：

```bash
kubectl apply -f lora-finetune-pod.yaml
```

**验证Pod状态：**

```bash
kubectl get pods

```
## 4. 启动LoRA微调

一旦pod处于"Running"状态，使用以下命令连接到它：

```bash
kubectl exec -it lora-finetune-app -- /bin/bash
```

在运行启动脚本`01__launch_training.sh`之前，您需要设置一个包含您的HuggingFace令牌的环境变量。访问令牌可在Hugging Face网站的Settings → Access Tokens下找到。

```bash
export HF_TOKEN=<your-huggingface-token>

./01__launch_training.sh
```

脚本完成后，您可以通过检查训练作业的日志来验证训练进度。

接下来，我们需要合并适配器分片并合并模型。为此，我们通过使用'-i'参数传入检查点的位置，并使用'-o'参数提供您想要保存合并模型的位置，运行Python脚本`02__consolidate_adapter_shards_and_merge_model.py`。
```
python3 ./02__consolidate_adapter_shards_and_merge_model.py -i /shared/finetuned_models/20250220_170215/checkpoint-250/ -o /shared/tuned_model/20250220_170215
```

脚本完成后，我们可以通过使用'-m'参数传入调优模型的位置来运行`03__test_model.py`测试微调后的模型。
```bash
./03__test_model.py -m /shared/tuned_model/20250220_170215
```

测试完模型后，您可以退出pod的交互式终端。

### 清理

要删除使用此解决方案创建的资源，请确保您位于data-on-eks仓库的根文件夹后执行以下命令：

```bash
# 删除Kubernetes资源：
cd gen-ai/training/llama-lora-finetuning-trn1
kubectl delete -f lora-finetune-pod.yaml

# 清理EKS集群和相关资源：
cd ../../../ai-ml/trainium-inferentia
./cleanup.sh
```
