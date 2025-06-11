---
id: migration-announcement
title: "🚨 仓库拆分：EKS上的数据和EKS上的AI"
sidebar_position: 0
---

# 🔥 EKS上的数据正在演变：介绍EKS上的AI

:::note

这是关于本仓库未来和我们蓝图结构即将发生变化的重要公告。
:::


## 📣 为什么要改变？

**EKS上的数据**项目随着时间的推移显著增长，通过生产就绪的蓝图、模式和最佳实践，在Amazon EKS上支持**数据分析**和**AI/ML**社区。

随着社区的发展和对更专注内容的需求变得明确，我们正在**将这个仓库分成两个不同的专业项目**：

- 📊 **`data-on-eks`** – 这个仓库（您现在所在的位置！）将继续提供**数据分析蓝图和模式**，包括Amazon EMR on EKS、Apache Spark、Flink、Kafka、Trino和其他相关框架。
- 🤖 **`ai-on-eks`** – 一个新的专用仓库，将服务于**AI/ML工作负载**，包括Terraform模块、训练管道、推理服务、LLM部署模式和GPU性能基准测试。


## 🗓️ 时间表

- **`ai-on-eks`软启动**：_KubeCon EU（伦敦），2025年4月第一周_
- **完全迁移和公开发布**：_2025年4月底前_

我们将在软启动期间和之后提供详细公告和URL，以帮助贡献者和用户轻松过渡。


## 🔎 您需要了解的内容

这一变化对贡献者和用户意味着：

1. **🚫 AI/ML拉取请求（PR）目前已暂停**在此仓库中。请暂时不要提交新的AI相关蓝图或模块，直到`ai-on-eks`仓库公开可用。
2. **✅ 现有AI蓝图将暂时保留**在这个`data-on-eks`仓库中。一旦新的`ai-on-eks`仓库完全启动，所有新内容和更新将在那里进行。
3. **📦 一旦迁移完成**，对现有AI/ML蓝图的更新将不再在`data-on-eks`仓库中进行。但是，我们将暂时保留这些蓝图，直到所有相关博客和文档都已更新，引用新的`ai-on-eks`仓库。
4. **🔗 现有的AWS博客、研讨会和文档**，目前指向`data-on-eks`仓库的将保持不变，以避免链接断开。我们将根据资源可用性，随着时间的推移，提出单独的问题来更新这些引用到新的`ai-on-eks`仓库。
5. **💬 今后，所有与EKS上的AI相关的新问题**，无论是新内容还是对现有蓝图的更新，都应在`ai-on-eks`仓库中提出。除非特定蓝图或内容仅存在于此仓库中且尚未迁移，否则我们不会在`data-on-eks`中处理与EKS上的AI相关的问题。


## ✅ 这个仓库中保留什么？

这个仓库（`data-on-eks`）将继续专注于：

- 📊 数据分析模式：EKS上的Spark、Trino、Flink和其他分析框架

- 🔁 流处理平台：Kafka、Apache Pulsar和其他事件驱动系统

- 🧩 作业调度器：使用Apache Airflow和YuniKorn等工具的Kubernetes原生作业编排

- 🗃️ 分布式数据库：EKS上的可扩展数据存储，如Apache Pinot、ClickHouse和PostgreSQL

- 📦 Terraform模块：与数据工作负载相关的基础设施即代码模板

- 🌐 网站和文档内容：包括这个Docusaurus站点

- 🛠️ 最佳实践、基准测试和资源：所有特定于数据基础设施和操作的内容

## 🚀 什么将移至新的ai-on-eks仓库？

以下组件正在迁移到新的ai-on-eks仓库（即将推出）：

- 🤖 [EKS上的AI](https://awslabs.github.io/data-on-eks../..../../docs/gen-ai)部分：包括当前托管在../..../../docs/gen-ai下的模型训练、推理和服务模式

- 🛠️ [AI Terraform模块](https://github.com/awslabs/data-on-eks/tree/main/ai-ml)：用于部署端到端AI工作负载的IaC模板

- 🧠 [生成式AI模式](https://github.com/awslabs/data-on-eks/tree/main/gen-ai)：训练和推理模式的代码

- 🛠️ AI特定最佳实践：针对EKS上AI/ML用例的指导、架构建议和扩展模式

## ❤️ 感谢

我们深深感谢您对**EKS上的数据**项目的反馈、支持和贡献。这一变化帮助我们为数据和AI/ML工作负载构建更专注、可扩展和生产级的解决方案。

请继续关注，随着我们接近4月的KubeCon EU，将会有更多详细信息。我们迫不及待地想与您分享接下来的内容！

— *EKS上的数据和AI维护者团队*
