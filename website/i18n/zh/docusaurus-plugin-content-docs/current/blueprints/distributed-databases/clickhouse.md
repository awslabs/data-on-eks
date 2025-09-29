---
sidebar_position: 4
sidebar_label: ClickHouse
---
# ClickHouse on EKS
[ClickHouse](https://clickhouse.com/) 是一个高性能、面向列的 SQL 数据库管理系统 (DBMS)，用于在线分析处理 (OLAP)，在 Apache 2.0 许可证下开源。

OLAP 是一种软件技术，您可以使用它从不同角度分析业务数据。组织从多个数据源收集和存储数据，如网站、应用程序、智能电表和内部系统。OLAP 通过将这些数据组合和分组到类别中来帮助组织处理和受益于不断增长的信息量，为战略规划提供可操作的见解。例如，零售商存储其销售的所有产品的数据，如颜色、尺寸、成本和位置。零售商还在不同的系统中收集客户购买数据，如订购商品的名称和总销售价值。OLAP 结合数据集来回答诸如哪种颜色的产品更受欢迎或产品放置如何影响销售等问题。

**ClickHouse 的一些关键优势包括：**

* 实时分析：ClickHouse 可以处理实时数据摄取和分析，使其适用于监控、日志记录和事件数据处理等用例。
* 高性能：ClickHouse 针对分析工作负载进行了优化，提供快速查询执行和高吞吐量。
* 可扩展性：ClickHouse 设计为跨多个节点水平扩展，允许用户在分布式集群中存储和处理 PB 级数据。它支持分片和复制以实现高可用性和容错性。
* 面向列的存储：ClickHouse 按列而不是按行组织数据，这允许高效压缩和更快的查询处理，特别是对于涉及聚合和大数据集扫描的查询。
* SQL 支持：ClickHouse 支持 SQL 的子集，使其对已经熟悉基于 SQL 的数据库的开发人员和分析师来说熟悉且易于使用。
* 集成数据格式：ClickHouse 支持各种数据格式，包括 CSV、JSON、Apache Avro 和 Apache Parquet，使其在摄取和查询不同类型的数据方面具有灵活性。

**要在 EKS 上部署 ClickHouse**，我们推荐来自 Altinity 的这个 [ClickHouse on EKS 蓝图](https://github.com/Altinity/terraform-aws-eks-clickhouse)，Altinity 是维护 [ClickHouse Kubernetes Operator](https://github.com/Altinity/clickhouse-operator) 的 AWS 合作伙伴。如果您对蓝图或操作器有任何问题，请在相应的 Altinity GitHub 存储库上创建问题。
