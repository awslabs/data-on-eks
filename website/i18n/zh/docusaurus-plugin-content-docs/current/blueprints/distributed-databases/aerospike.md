---
sidebar_position: 5
sidebar_label: Aerospike
---

# Aerospike Database Enterprise on EKS
[Aerospike Database Enterprise Edition](https://aerospike.com) 是一个高性能、分布式 NoSQL 数据库，专为实时、关键任务应用程序而设计。将 Aerospike 与 Amazon Elastic Kubernetes Service (EKS) 集成，结合了 Aerospike 强大的数据管理能力和 Kubernetes 编排能力。这种集成使组织能够在 EKS 灵活且有弹性的环境中利用 Aerospike 可预测的亚毫秒性能和无缝可扩展性。通过利用 [Aerospike Kubernetes Operator (AKO)](https://aerospike.com/docs/cloud/kubernetes/operator)，在 EKS 上部署和管理 Aerospike 集群是自动化的，确保高效运营并降低复杂性。

## EKS 上 Aerospike 的主要优势
* **可预测的低延迟**：Aerospike 确保亚毫秒响应时间，这对于需要即时数据访问的应用程序至关重要，如欺诈检测、推荐引擎和实时竞价系统。

* **无缝可扩展性**：Aerospike 的混合内存架构允许高效的水平和垂直扩展，在不影响性能的情况下容纳从 TB 到 PB 的数据增长。在 EKS 上部署可实现动态资源分配，有效满足不同的工作负载需求。

* **高可用性和弹性**：通过跨数据中心复制 (XDR) 等功能，Aerospike 为跨地理分散集群的异步数据复制提供细粒度控制。这确保了数据可用性并符合数据本地化法规。EKS 通过在多个可用区分布工作负载来增强这种弹性。

* **运营效率**：Aerospike Kubernetes Operator 自动化日常任务，如配置、扩展和升级 Aerospike 集群。这降低了运营复杂性和开销，使团队能够专注于交付价值而不是管理基础设施。

* **成本优化**：利用 Aerospike 的高效资源使用和 EKS 的灵活基础设施，组织可以与传统部署相比实现显著的成本节约。Aerospike 以减少的硬件占用空间提供高性能的能力转化为更低的总拥有成本。

## 社区和支持
如需帮助和与社区互动：
* **Aerospike 文档**：[Aerospike 文档](https://aerospike.com/docs)中提供了全面的指南和参考。

* **GitHub 存储库**：在 aerospike-kubernetes-operator [GitHub 存储库](https://github.com/aerospike/aerospike-kubernetes-operator)访问 AKO 源代码、报告问题和贡献。

* **社区论坛**：在 [Aerospike 社区论坛](https://discuss.aerospike.com)加入讨论并寻求建议。

通过在 Amazon EKS 上部署 Aerospike Database Enterprise Edition，组织可以利用 Aerospike 高性能数据管理和 Kubernetes 编排能力的结合优势，为实时数据应用程序提供可扩展、有弹性且经济高效的解决方案。

## 在 EKS 上部署 Aerospike
要在 EKS 集群上部署 Aerospike Database Enterprise Edition，我们建议使用由 Aerospike 维护的 [Aerospike on EKS 蓝图](https://github.com/aerospike/aerospike-terraform-aws-eks)，Aerospike 是 AWS 合作伙伴和 [Aerospike Kubernetes Operator](https://github.com/aerospike/aerospike-kubernetes-operator) 的维护者。

如果您遇到蓝图或操作器的任何问题，请在相关的 Aerospike GitHub 存储库上报告。
