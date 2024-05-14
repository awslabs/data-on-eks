---
sidebar_position: 4
sidebar_label: ClickHouse
---
# ClickHouse on EKS
[ClickHouse](https://clickhouse.com/) is a high-performance, column-oriented SQL database management system (DBMS) for online analytical processing (OLAP) that is open sourced under the Apache 2.0 license.


OLAP is software technology you can use to analyze business data from different points of view. Organizations collect and store data from multiple data sources, such as websites, applications, smart meters, and internal systems. OLAP helps organizations process and benefit from a growing amount of information by combining and groups this data into categories to provide actionable insights for strategic planning. For example, a retailer stores data about all the products it sells, such as color, size, cost, and location. The retailer also collects customer purchase data, such as the name of the items ordered and total sales value, in a different system. OLAP combines the datasets to answer questions such as which color products are more popular or how product placement impacts sales.

**Some key benefits of Clickhouse include:**

* Real-Time Analytics: ClickHouse can handle real-time data ingestion and analysis, making it suitable for use cases such as monitoring, logging, and event data processing.
* High Performance: ClickHouse is optimized for analytical workloads, providing fast query execution and high throughput.
* Scalability: ClickHouse is designed to scale horizontally across multiple nodes, allowing users to store and process petabytes of data across a distributed cluster. It supports sharding and replication for high availability and fault tolerance.
* Column-Oriented Storage: ClickHouse organizes data by columns rather than rows, which allows for efficient compression and faster query processing, especially for queries that involve aggregations and scans of large datasets.
* SQL Support: ClickHouse supports a subset of SQL, making it familiar and easy to use for developers and analysts who are already familiar with SQL-based databases.
* Integrated Data Formats: ClickHouse supports various data formats, including CSV, JSON, Apache Avro, and Apache Parquet, making it flexible for ingesting and querying different types of data.

**To deploy Clickhouse on EKS**, we recommend this [Clickhouse on EKS blueprint](https://github.com/Altinity/terraform-aws-eks-clickhouse) from Altinity, an AWS Partner who maintains the [Clickouse Kubernetes Operator](https://github.com/Altinity/clickhouse-operator). If you have any issues with the blueprint or operator, please create an issue on the corresponding Altinity GitHub repository.
