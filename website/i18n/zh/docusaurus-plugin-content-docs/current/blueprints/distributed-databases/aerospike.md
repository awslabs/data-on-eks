---
sidebar_position: 5
sidebar_label: Aerospike
---

# EKS上的Aerospike数据库企业版
[Aerospike数据库企业版](https://aerospike.com)是一个高性能、分布式NoSQL数据库，专为实时、关键任务应用程序设计。将Aerospike与Amazon Elastic Kubernetes Service (EKS)集成，结合了Aerospike强大的数据管理能力和Kubernetes的编排能力。这种集成使组织能够在EKS灵活且弹性的环境中利用Aerospike的可预测的亚毫秒级性能和无缝扩展性。通过利用[Aerospike Kubernetes Operator (AKO)](https://aerospike.com/docs/cloud/kubernetes/operator)，在EKS上部署和管理Aerospike集群的过程实现了自动化，确保高效运营并降低复杂性。

## Aerospike在EKS上的主要优势
* **可预测的低延迟**：Aerospike确保亚毫秒级响应时间，这对于需要即时数据访问的应用程序至关重要，如欺诈检测、推荐引擎和实时竞价系统。

* **无缝扩展性**：Aerospike的混合内存架构允许高效的水平和垂直扩展，在不影响性能的情况下适应从TB到PB级的数据增长。在EKS上部署可以实现动态资源分配，有效满足不同工作负载的需求。

* **高可用性和弹性**：通过跨数据中心复制(XDR)等功能，Aerospike为地理分散集群之间的异步数据复制提供了精细控制。这确保了数据可用性并符合数据本地化法规。EKS通过将工作负载分布在多个可用区，增强了这种弹性。

* **运营效率**：Aerospike Kubernetes Operator自动化了配置、扩展和升级Aerospike集群等常规任务。这减少了运营复杂性和开销，使团队能够专注于交付价值而不是管理基础设施。

* **成本优化**：利用Aerospike高效使用资源和EKS灵活的基础设施，组织可以与传统部署相比实现显著的成本节约。Aerospike能够以较小的硬件占用提供高性能，从而降低总体拥有成本。

## 社区和支持
如需帮助并与社区互动：
* **Aerospike文档**：[Aerospike文档](https://aerospike.com/docs)中提供了全面的指南和参考资料。

* **GitHub仓库**：在aerospike-kubernetes-operator [GitHub仓库](https://github.com/aerospike/aerospike-kubernetes-operator)访问AKO源代码、报告问题和贡献。

* **社区论坛**：加入[Aerospike社区论坛](https://discuss.aerospike.com)的讨论并寻求建议。

通过在Amazon EKS上部署Aerospike数据库企业版，组织可以利用Aerospike高性能数据管理和Kubernetes编排能力的组合优势，为实时数据应用程序提供可扩展、弹性和经济高效的解决方案。

## 在EKS上部署Aerospike
要在EKS集群上部署Aerospike数据库企业版，我们建议使用由Aerospike维护的[EKS上的Aerospike蓝图](https://github.com/aerospike/aerospike-terraform-aws-eks)，Aerospike是AWS合作伙伴和[Aerospike Kubernetes Operator](https://github.com/aerospike/aerospike-kubernetes-operator)的维护者。

如果您在使用蓝图或操作符时遇到任何问题，请在相关的Aerospike GitHub仓库上报告。
