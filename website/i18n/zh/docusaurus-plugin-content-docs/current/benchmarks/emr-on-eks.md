---
sidebar_position: 1
sidebar_label: EMR on EKS 基准测试
---

# Amazon EMR on Amazon EKS 为 Spark 工作负载提供高达 61% 的成本降低和高达 68% 的性能提升

Amazon EMR on Amazon EKS 是 Amazon EMR 提供的一个部署选项，使您能够以经济高效的方式在 Amazon Elastic Kubernetes Service (Amazon EKS) 上运行 Apache Spark 应用程序。它使用 Apache Spark 的 EMR 运行时来提高性能，使您的作业运行更快、成本更低。

在我们使用 3 TB 规模的 TPC-DS 数据集进行的基准测试中，我们观察到与在 Amazon EKS 上通过等效配置运行开源 Apache Spark 相比，Amazon EMR on EKS 提供高达 61% 的成本降低和高达 68% 的性能提升。在这篇文章中，我们将介绍性能测试过程，分享结果，并讨论如何重现基准测试。我们还分享了一些优化作业性能的技术，这些技术可能为您的 Spark 工作负载带来进一步的成本优化。

## Amazon EMR on EKS 如何降低成本并提高性能？

Spark 的 EMR 运行时是 Apache Spark 的性能优化运行时，与开源 Apache Spark 100% API 兼容。它在 Amazon EMR on EKS 中默认启用。它有助于更快地运行 Spark 工作负载，从而降低运行成本。它包括多个性能优化功能，如自适应查询执行 (AQE)、动态分区修剪、标量子查询扁平化、布隆过滤器连接等。

除了 Spark 的 EMR 运行时带来的成本优势外，Amazon EMR on EKS 还可以利用其他 AWS 功能进一步优化成本。例如，您可以在 Amazon Elastic Compute Cloud (Amazon EC2) Spot 实例上运行 Amazon EMR on EKS 作业，与按需实例相比，可节省高达 90% 的成本。此外，Amazon EMR on EKS 支持基于 Arm 的 Graviton EC2 实例，与基于 Graviton2 的 M6g 与 M5 实例类型相比，可提供 15% 的性能提升和高达 30% 的成本节约。

最近的优雅执行器退役功能通过使 Spark 能够预测 Spot 实例中断，使 Amazon EMR on EKS 工作负载更加稳健。无需重新计算或重新运行受影响的 Spark 作业，Amazon EMR on EKS 可以通过关键的稳定性和性能改进进一步降低作业成本。

此外，通过容器技术，Amazon EMR on EKS 提供更多选项来调试和监控 Spark 作业。例如，您可以选择 Spark History Server、Amazon CloudWatch 或 Amazon Managed Prometheus 和 Amazon Managed Grafana（有关更多详细信息，请参阅监控和日志记录研讨会）。可选地，您可以使用熟悉的命令行工具（如 kubectl）与作业处理环境交互并实时观察 Spark 作业，这提供了快速失败和高效的开发体验。

Amazon EMR on EKS 支持多租户需求，并通过作业执行角色提供应用程序级安全控制。它能够无缝集成到其他 AWS 原生服务，而无需在 Amazon EKS 中设置密钥对。简化的安全设计可以减少您的工程开销并降低数据泄露的风险。此外，Amazon EMR on EKS 处理安全和性能补丁，因此您可以专注于构建应用程序。

## 基准测试
这篇文章提供了端到端的 Spark 基准测试解决方案，因此您可以亲身体验性能测试过程。该解决方案使用未修改的 TPC-DS 数据模式和表关系，但从 TPC-DS 派生查询以支持 Spark SQL 测试用例。它不能与其他已发布的 TPC-DS 基准测试结果进行比较。

关键概念
事务处理性能委员会决策支持 (TPC-DS) 是一个决策支持基准测试，用于评估大数据技术的分析性能。我们的测试数据是基于 TPC-DS 标准规范修订版 2.4 文档的 TPC-DS 兼容数据集，该文档概述了业务模型和数据模式、关系等。如白皮书所示，测试数据包含 7 个事实表和 17 个维度表，平均有 18 列。该模式包含基本的零售商业务信息，如经典销售渠道的客户、订单和商品数据：商店、目录和互联网。此源数据旨在表示具有常见数据倾斜的真实业务场景，如季节性销售和频繁名称。此外，TPC-DS 基准测试基于原始数据的近似大小提供一组离散的缩放点（缩放因子）。在我们的测试中，我们选择了 3 TB 缩放因子，它产生 177 亿条记录，Parquet 文件格式中大约 924 GB 的压缩数据。

测试方法
单个测试会话包含 104 个按顺序运行的 Spark SQL 查询。为了获得公平的比较，每种不同部署类型的会话（如 Amazon EMR on EKS）都运行三次。我们在这篇文章中分析和讨论的是这三次迭代的每个查询的平均运行时间。最重要的是，它派生出两个汇总指标来表示我们的 Spark 性能：

总执行时间 – 三次迭代平均运行时间的总和
几何平均值 – 平均运行时间的几何平均值

测试结果
在测试结果摘要中（见下图），我们发现 Amazon EMR on EKS 使用的 Amazon EMR 优化 Spark 运行时在几何平均值方面比 Amazon EKS 上的开源 Spark 好约 2.1 倍，在总运行时间方面快 3.5 倍。

![img1.png](../../../../../docs/benchmarks/img1.png)

下图按查询分解了性能摘要。我们观察到与开源 Spark 相比，Spark 的 EMR 运行时在每个查询中都更快。查询 q67 是性能测试中最长的查询。使用开源 Spark 的平均运行时间为 1019.09 秒。然而，使用 Amazon EMR on EKS 需要 150.02 秒，快了 6.8 倍。这些长时间运行查询中最高的性能提升是 q72—319.70 秒（开源 Spark）与 26.86 秒（Amazon EMR on EKS），提升了 11.9 倍。

![img2.png](../../../../../docs/benchmarks/img2.png)

完整[博客链接](https://aws.amazon.com/blogs/big-data/amazon-emr-on-amazon-eks-provides-up-to-61-lower-costs-and-up-to-68-performance-improvement-for-spark-workloads/)
