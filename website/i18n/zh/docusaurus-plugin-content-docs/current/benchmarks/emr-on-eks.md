---
sidebar_position: 1
sidebar_label: EMR on EKS 基准测试
---

# Amazon EMR on Amazon EKS为Spark工作负载提供高达61%的成本降低和高达68%的性能提升

Amazon EMR on Amazon EKS是Amazon EMR提供的一种部署选项，使您能够以经济高效的方式在Amazon Elastic Kubernetes Service (Amazon EKS)上运行Apache Spark应用程序。它使用EMR运行时环境来提高Apache Spark的性能，使您的作业运行更快，成本更低。

在我们使用3 TB规模的TPC-DS数据集进行的基准测试中，我们观察到与通过等效配置在Amazon EKS上运行开源Apache Spark相比，Amazon EMR on EKS提供了高达61%的成本降低和高达68%的性能提升。在本文中，我们将介绍性能测试过程，分享结果，并讨论如何重现基准测试。我们还分享了一些优化作业性能的技术，这些技术可能会进一步优化您的Spark工作负载成本。

## Amazon EMR on EKS如何降低成本并提高性能？

EMR运行时环境是为Apache Spark优化性能的运行时环境，与开源Apache Spark 100%API兼容。它在Amazon EMR on EKS中默认启用。它有助于更快地运行Spark工作负载，从而降低运行成本。它包括多种性能优化功能，如自适应查询执行(AQE)、动态分区修剪、扁平化标量子查询、布隆过滤器连接等。

除了EMR运行时环境为Spark带来的成本优势外，Amazon EMR on EKS还可以利用其他AWS功能进一步优化成本。例如，您可以在Amazon Elastic Compute Cloud (Amazon EC2) Spot实例上运行Amazon EMR on EKS作业，与按需实例相比，可节省高达90%的成本。此外，Amazon EMR on EKS支持基于Arm的Graviton EC2实例，与基于Graviton2的M6g与M5实例类型相比，可提高15%的性能并降低高达30%的成本。

最近的优雅执行器退役功能通过使Spark能够预测Spot实例中断，使Amazon EMR on EKS工作负载更加稳健。无需重新计算或重新运行受影响的Spark作业，Amazon EMR on EKS可以通过关键的稳定性和性能改进进一步降低作业成本。

此外，通过容器技术，Amazon EMR on EKS提供了更多选项来调试和监控Spark作业。例如，您可以选择Spark History Server、Amazon CloudWatch或Amazon Managed Prometheus和Amazon Managed Grafana（有关更多详细信息，请参阅监控和日志记录研讨会）。或者，您可以使用熟悉的命令行工具（如kubectl）与作业处理环境交互并实时观察Spark作业，这提供了快速失败和高效的开发体验。

Amazon EMR on EKS支持多租户需求，并通过作业执行角色提供应用程序级安全控制。它实现了与其他AWS原生服务的无缝集成，无需在Amazon EKS中设置密钥对。简化的安全设计可以减少您的工程开销并降低数据泄露的风险。此外，Amazon EMR on EKS处理安全和性能补丁，因此您可以专注于构建应用程序。

## 基准测试
本文提供了一个端到端的Spark基准解决方案，以便您可以亲身体验性能测试过程。该解决方案使用未修改的TPC-DS数据架构和表关系，但从TPC-DS派生查询以支持Spark SQL测试用例。它与其他已发布的TPC-DS基准结果不具可比性。

关键概念
交易处理性能委员会-决策支持(TPC-DS)是一个决策支持基准，用于评估大数据技术的分析性能。我们的测试数据是基于TPC-DS标准规范2.4版文档的TPC-DS兼容数据集，该文档概述了业务模型和数据架构、关系等。正如白皮书所示，测试数据包含7个事实表和17个维度表，平均有18列。该架构包含零售商业务的基本信息，如客户、订单和商品数据，适用于传统销售渠道：商店、目录和互联网。这些源数据旨在代表具有常见数据偏斜的真实世界业务场景，如季节性销售和常见名称。此外，TPC-DS基准提供了一组基于原始数据近似大小的离散缩放点（缩放因子）。在我们的测试中，我们选择了3 TB缩放因子，它产生了177亿条记录，约924 GB的Parquet文件格式压缩数据。

测试方法
一个测试会话由104个按顺序运行的Spark SQL查询组成。为了进行公平比较，每个不同部署类型（如Amazon EMR on EKS）的会话都运行了三次。我们在本文中分析和讨论的是这三次迭代的每个查询的平均运行时间。最重要的是，它派生出两个汇总指标来表示我们的Spark性能：

总执行时间 – 三次迭代的平均运行时间之和
几何平均值 – 平均运行时间的几何平均值
测试结果
在测试结果摘要（见下图）中，我们发现Amazon EMR on EKS使用的Amazon EMR优化Spark运行时在几何平均值上比Amazon EKS上的开源Spark好约2.1倍，总运行时间快3.5倍。

![img1.png](../../../../../docs/benchmarks/img1.png)

下图按查询细分了性能摘要。我们观察到，与开源Spark相比，EMR运行时环境在每个查询中都更快。查询q67是性能测试中最长的查询。使用开源Spark的平均运行时间为1019.09秒。然而，使用Amazon EMR on EKS只需要150.02秒，快了6.8倍。这些长时间运行查询中性能提升最高的是q72—319.70秒（开源Spark）与26.86秒（Amazon EMR on EKS），提升了11.9倍。

![img2.png](../../../../../docs/benchmarks/img2.png)

完整[博客链接](https://aws.amazon.com/blogs/big-data/amazon-emr-on-amazon-eks-provides-up-to-61-lower-costs-and-up-to-68-performance-improvement-for-spark-workloads/)
