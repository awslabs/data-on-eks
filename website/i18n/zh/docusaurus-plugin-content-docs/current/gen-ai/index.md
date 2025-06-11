---
sidebar_position: 1
sidebar_label: 概述
---

# EKS上的生成式AI

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

欢迎来到[Amazon Elastic Kubernetes Service (EKS)](https://aws.amazon.com/eks/)上的生成式AI，这是您利用大型语言模型(LLM)强大功能的门户，可用于各种应用。本介绍页面作为您探索我们提供的训练、微调和推理服务的起点，这些服务使用各种LLM，包括BERT-Large、Llama2、Stable Diffusion等。

我们的平台提供多种模式，使用户能够通过一套全面的开源ML工具/框架在EKS上扩展其生成式AI工作负载。

下面是说明这些工具在EKS中集成的架构图：

![EKS上的开源ML平台](../../../../../docs/gen-ai/ml-platforms-eks.png)

## [训练](https://awslabs.github.io/data-on-eks/docs/category/training-on-eks)
在生成式AI世界中，训练涉及教导模型通过从大量数据中学习来理解和生成类似人类的文本。这个过程至关重要，因为它构成了BERT-Large和Llama2等模型的基础，使它们能够执行各种任务，如文本摘要、翻译等。有效的训练确保模型能够理解复杂的模式并生成连贯、符合上下文的响应。

我们的平台支持各种ML框架，包括PyTorch、TensorFlow、TensorRT和vLLM。您可以使用JupyterHub进行交互式和协作式模型开发，在那里您可以执行数据分析、构建模型和运行实验。训练阶段还与Kubeflow和Ray集成，为管理复杂的机器学习工作流提供强大的解决方案，从数据预处理到训练和评估。

您准备好深入LLM的世界并为您的特定需求训练模型了吗？探索我们全面的训练资源以开始。

## [推理](https://awslabs.github.io/data-on-eks/docs/category/inference-on-eks)
推理是使用训练好的模型基于新的输入数据进行预测或生成输出的过程。在生成式AI的背景下，推理使模型能够实时执行文本生成、翻译和摘要等任务。构建可扩展的推理平台对于处理高需求并确保低延迟至关重要，这对于需要实时响应的应用程序尤为重要。

释放LLM在强大推理任务中的潜力。我们的推理资源将指导您有效部署LLM。利用RayServe、NVIDIA Triton推理服务器和KServe等部署工具确保高性能模型服务。我们还提供使用AWS Neuron for Inferentia和NVIDIA GPU的优化技术来加速推理。本节包括设置推理端点、扩展部署以处理不同负载以及监控性能以保持可靠性和效率的分步说明。

## 存储和数据管理
高效的数据存储和管理是成功的AI/ML操作的基础。我们的平台与AWS存储解决方案（如S3、EBS、EFS和FSx）集成，以确保可扩展和可靠的数据处理。利用MLflow进行模型注册和版本控制，并使用Amazon ECR管理容器镜像。这确保了从模型开发到部署的无缝工作流，并有强大的数据管理实践支持您的ML生命周期。

无论您是经验丰富的从业者还是该领域的新手，我们在EKS上的生成式AI功能使您能够利用语言建模的最新进展。深入每个部分开始您的旅程，并探索如何利用这些工具和框架在Amazon EKS上构建、微调和部署强大的AI模型。
