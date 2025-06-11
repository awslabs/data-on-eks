---
sidebar_position: 4
sidebar_label: ClickHouse
---
# ClickHouse on EKS
[ClickHouse](https://clickhouse.com/)是一个高性能、面向列的SQL数据库管理系统(DBMS)，用于在线分析处理(OLAP)，在Apache 2.0许可下开源。


OLAP是一种软件技术，您可以使用它从不同角度分析业务数据。组织从多个数据源收集和存储数据，如网站、应用程序、智能仪表和内部系统。OLAP通过将这些数据组合并分组到不同类别中，帮助组织处理并从不断增长的信息中受益，为战略规划提供可行的见解。例如，零售商存储有关其销售的所有产品的数据，如颜色、尺寸、成本和位置。零售商还在不同系统中收集客户购买数据，如订购商品的名称和总销售价值。OLAP结合这些数据集来回答诸如哪种颜色的产品更受欢迎或产品放置如何影响销售等问题。

**Clickhouse的一些主要优势包括：**

* 实时分析：ClickHouse可以处理实时数据摄取和分析，使其适用于监控、日志记录和事件数据处理等用例。
* 高性能：ClickHouse针对分析工作负载进行了优化，提供快速查询执行和高吞吐量。
* 可扩展性：ClickHouse设计为可以在多个节点上水平扩展，允许用户在分布式集群中存储和处理PB级数据。它支持分片和复制，以实现高可用性和容错性。
* 面向列的存储：ClickHouse按列而不是按行组织数据，这允许高效压缩和更快的查询处理，特别是对于涉及大型数据集聚合和扫描的查询。
* SQL支持：ClickHouse支持SQL的一个子集，使已经熟悉基于SQL的数据库的开发人员和分析师易于使用和熟悉。
* 集成数据格式：ClickHouse支持各种数据格式，包括CSV、JSON、Apache Avro和Apache Parquet，使其在摄取和查询不同类型的数据方面具有灵活性。

**要在EKS上部署Clickhouse**，我们推荐来自Altinity的这个[ClickHouse on EKS蓝图](https://github.com/Altinity/terraform-aws-eks-clickhouse)，Altinity是维护[Clickouse Kubernetes operator](https://github.com/Altinity/clickhouse-operator)的AWS合作伙伴。如果您对蓝图或 operator有任何问题，请在相应的Altinity GitHub仓库上创建问题。
