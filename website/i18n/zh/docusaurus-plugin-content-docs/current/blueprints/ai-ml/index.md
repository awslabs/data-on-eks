---
sidebar_position: 1
sidebar_label: 介绍
---

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

# Amazon EKS上的AI/ML平台

Amazon Elastic Kubernetes Service (EKS)是一个强大的、托管的Kubernetes平台，已成为在云中部署和管理AI/ML工作负载的基石。凭借其处理复杂、资源密集型任务的能力，Amazon EKS为运行AI/ML模型提供了可扩展和灵活的基础，使其成为旨在充分利用机器学习潜力的组织的理想选择。

## Amazon EKS上AI/ML平台的主要优势

### 1. 可扩展性和灵活性
Amazon EKS使组织能够无缝扩展AI/ML工作负载。无论您是训练需要大量计算能力的大型语言模型，还是部署需要处理不可预测流量模式的推理管道，EKS都能高效地进行扩展和缩减，优化资源使用和成本。

### 2. 使用GPU和Neuron实例实现高性能
Amazon EKS支持广泛的计算选项，包括GPU和AWS Neuron实例，这些对于加速AI/ML工作负载至关重要。这种支持允许高性能训练和低延迟推理，确保模型在生产环境中高效运行。

### 3. 与AI/ML工具集成
Amazon EKS与流行的AI/ML工具和框架（如TensorFlow、PyTorch和Ray）无缝集成，为数据科学家和工程师提供了熟悉且强大的生态系统。这些集成使用户能够利用现有工具，同时受益于Kubernetes的可扩展性和管理功能。

### 4. 自动化和管理
Amazon EKS上的Kubernetes自动化了与管理AI/ML工作负载相关的许多操作任务。自动扩展、滚动更新和自我修复等功能确保您的应用程序保持高可用性和弹性，减少了手动干预的开销。

### 5. 安全性和合规性
在Amazon EKS上运行AI/ML工作负载提供了强大的安全功能，包括细粒度的IAM角色、加密和网络策略，确保敏感数据和模型受到保护。EKS还遵守各种合规标准，使其适合具有严格监管要求的企业。

## 为什么选择Amazon EKS进行AI/ML？

Amazon EKS提供了一个全面的、托管的环境，简化了AI/ML模型的部署，同时提供了生产工作负载所需的性能、可扩展性和安全性。凭借其与各种AI/ML工具集成的能力以及对高级计算资源的支持，EKS使组织能够加速其AI/ML计划并大规模交付创新解决方案。

通过选择Amazon EKS，您可以访问一个强大的基础设施，能够处理现代AI/ML工作负载的复杂性，使您能够专注于创新和价值创造，而不是管理底层系统。无论您是部署简单模型还是复杂的AI系统，Amazon EKS都提供了在竞争激烈且快速发展的领域取得成功所需的工具和功能。

## 在Amazon EKS上部署生成式AI模型

通过两个主要蓝图支持在Amazon EKS上部署生成式AI模型：

- **对于GPU**：使用[JARK堆栈蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/jark)。
- **对于Neuron**：从[EKS上的Trainium蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/trainium)开始。

除了这些之外，本节还提供了其他有价值的ML蓝图：

- **NVIDIA Spark RAPIDS**：对于GPU上的Spark工作负载，请参考[NVIDIA Spark RAPIDS蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/emr-spark-rapids)。

- **EKS上的JupyterHub**：探索[JupyterHub蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/jupyterhub)，它展示了时间切片和MIG功能，以及带有配置文件的多租户配置。这非常适合在EKS上部署大规模JupyterHub平台。

- **其他模式**：有关使用NVIDIA Triton服务器、NVIDIA NGC等的其他模式，请参考[生成式AI页面](https://awslabs.github.io/data-on-eks/docs/gen-ai)。
