---
sidebar_position: 3
sidebar_label: Trino on EKS
---

# 在 EKS 上部署 Trino

## 介绍

[Trino](https://trino.io/) 是一个开源、快速、分布式查询引擎，专为在多种数据源上运行大数据分析的 SQL 查询而设计，包括 Amazon S3、关系数据库、分布式数据存储和数据仓库。

当 Trino 执行查询时，它通过将执行分解为阶段层次结构来实现，这些阶段作为分布在 Trino worker 网络上的一系列任务来实现。Trino 集群由一个 coordinator 和许多用于并行处理的 worker 组成，可以作为 Kubernetes Pod 部署在 EKS 集群上。coordinator 和 worker 协作访问连接的数据源，模式和引用存储在目录中。要访问数据源，您可以使用 Trino 提供的许多[连接器](https://trino.io/docs/current/connector.html)之一来适配 Trino。示例包括 Hive、Iceberg 和 Kafka。有关 Trino 项目的更多详细信息可以在此[链接](https://trino.io)中找到

## 蓝图解决方案

此蓝图将在 EKS 集群（Kubernetes 版本 1.29）上部署 Trino，节点使用 Karpenter（v0.34.0）配置。为了优化成本和性能，Karpenter 将为 Trino coordinator 配置按需节点，为 Trino worker 配置 EC2 Spot 实例。借助 Trino 的多架构容器镜像，Karpenter [NodePool](https://karpenter.sh/v0.34/concepts/nodepools/) 将允许使用来自不同 CPU 架构的 EC2 实例配置节点，包括基于 AWS Graviton 的实例。Trino 使用[官方 Helm chart](https://trinodb.github.io/charts/charts/trino/) 部署，为用户提供自定义值以利用 Hive 和 Iceberg 连接器。示例将使用 AWS 上的 Glue 和 Iceberg 表作为后端数据源，使用 S3 作为存储。

## 部署解决方案

让我们来看看部署步骤。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [Trino CLI client](https://trino.io/docs/current/client/cli.html)
<details>
<summary> 切换查看 Trino CLI 安装步骤</summary>
```bash
wget https://repo1.maven.org/maven2/io/trino/trino-cli/427/trino-cli-427-executable.jar
mv trino-cli-427-executable.jar trino
chmod +x trino
```
</details>

### 使用 Trino 部署 EKS 集群

首先，克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到 `distributed-databases/trino` 并运行 `install.sh` 脚本。在提示时输入您要配置资源的 AWS 区域（例如，`us-west-2`）。

```bash
cd data-on-eks/distributed-databases/trino

./install.sh
```

### 验证部署

验证 Amazon EKS 集群

```bash
#选择您部署资源的区域
aws eks describe-cluster --name trino-on-eks --region us-west-2
```

更新本地 kubeconfig，以便我们可以访问 kubernetes 集群（您也可以从 terraform 输出 `configure_kubectl` 获取此命令）

```bash
aws eks update-kubeconfig --name trino-on-eks --region us-west-2
```

首先，让我们验证集群中有 Karpenter 配置的工作节点。让我们也看看它们的可用区和容量类型（按需或 spot）

```bash
kubectl get nodes --selector=karpenter.sh/nodepool=trino-sql-karpenter -L topology.kubernetes.io/zone -L karpenter.sh/capacity-type -L node.kubernetes.io/instance-type
```
#### 输出
```bash
NAME                                        STATUS   ROLES    AGE   VERSION               ZONE         CAPACITY-TYPE   INSTANCE-TYPE
ip-10-1-11-49.us-west-2.compute.internal    Ready    <none>   24m   v1.29.0-eks-5e0fdde   us-west-2b   on-demand       t4g.medium
```
我们可以看到上面 Karpenter 为运行 Trino coordinator 配置了按需节点。
:::info

对于像 Trino 这样在大规模并行处理集群上运行的分布式大数据查询引擎，建议在同一可用区中部署集群，以避免产生高跨可用区数据传输成本。这就是为什么 Karpenter NodePool 被配置为在同一可用区中启动 EKS 节点

:::

现在，让我们验证在 `trino` 命名空间中运行的 coordinator 和 worker Pod

```bash
kubectl get pods --namespace=trino
```
#### 输出
```bash
NAME                                 READY   STATUS    RESTARTS   AGE
trino-coordinator-5cfd685c8f-mchff   1/1     Running   0          37m
```

接下来，我们将端口转发 trino 服务，以便可以在本地访问它

```bash
kubectl -n trino port-forward service/trino 8080:8080
```

现在，让我们通过 Web 浏览器在 `http://localhost:8080` 访问 Trino UI，并在登录窗口中使用用户名 `admin` 登录，如下所示：

![Trino UI 登录](../../../../../../docs/blueprints/distributed-databases/img/trino-ui-login.PNG)

Trino Web UI 将显示 0 个活动 worker：

![Trino UI](../../../../../../docs/blueprints/distributed-databases/img/trino-ui.PNG)

## 使用 Trino 进行数据库查询执行

### 示例 #1：使用 Hive 连接器

在此示例中，我们将使用 AWS Glue 设置 Hive metastore，源数据存储在 S3 中，爬虫将从中推断模式以构建 Glue 表。

在 EKS 上使用 Trino 与 Glue 连接器，我们将使用 Trino CLI 运行示例 SQL 查询来检索数据。

#### 设置

从 `examples` 目录运行 hive 脚本，使用 2022 NYC Taxi 数据集（Parquet 格式）设置蓝图 S3 存储桶，并构建 Glue metastore：

```bash
cd examples/
./hive-setup.sh
```

您将看到一些输出显示进度，如果成功，将看到存储元数据的 Glue 表名称为 `hive`。

#### 运行查询
您应该已经安装了 Trino CLI 作为先决条件的一部分。蓝图已配置了 Hive 连接器与我们在上一节中设置的存储桶，因此您应该能够在不需要其他设置的情况下查询数据源。

首先，如果您已经关闭了上一节的会话，请端口转发您的 trino 服务以在本地访问它：
```
kubectl -n trino port-forward service/trino 8080:8080
```

在端口转发运行时，打开另一个终端选项卡，其中有 Trino CLI 并运行以下命令访问 coordinator：
```bash
./trino http://127.0.0.1:8080 --user admin
```

成功后，您将能够获得执行命令的提示符。您可以使用 `help` 命令查看支持的命令列表。您运行的第一个命令将触发 trino worker 从 0 自动扩展到 1，并需要几分钟才能完成。

例如：

要显示目录列表，运行查询 - `SHOW CATALOGS;`，您可以看到蓝图配置的 `hive` 和 `iceberg` 目录等
#### 输出
```bash
 Catalog
---------
 hive
 iceberg
 system
 tpcds
 tpch
(5 rows)

Query 20240215_200117_00003_6jdxw, FINISHED, 1 node
Splits: 1 total, 1 done (100.00%)
0.49 [0 rows, 0B] [0 rows/s, 0B/s]
```

要查看 Hive 目录中的模式（数据库），运行查询 - `SHOW SCHEMAS FROM hive;`：
#### 输出
```bash
  Schema
--------------------
 information_schema
 taxi_hive_database
(2 rows)
```

让我们使用 `taxi_hive_database` 并显示此数据库中的表 -
```
USE hive.taxi_hive_database;
```
```
SHOW TABLES;
```
#### 输出
```
Table
-------
hive
(1 row)
```

最后，运行一个简单的查询来列出项目 - `SELECT * FROM hive LIMIT 5;`
#### 输出
```
vendorid |  tpep_pickup_datetime   |  tpep_dropoff_datetime  | passenger_count | trip_distance | ratecodeid | store_and_fwd_flag | pulocationid | dolocation>
----------+-------------------------+-------------------------+-----------------+---------------+------------+--------------------+--------------+----------->
        1 | 2022-09-01 00:28:12.000 | 2022-09-01 00:36:22.000 |             1.0 |           2.1 |        1.0 | N                  |          100 |          2>
        1 | 2022-11-01 00:24:49.000 | 2022-11-01 00:31:04.000 |             2.0 |           1.0 |        1.0 | N                  |          158 |          1>
        1 | 2022-11-01 00:37:32.000 | 2022-11-01 00:42:23.000 |             2.0 |           0.8 |        1.0 | N                  |          249 |          1>
        2 | 2022-09-01 00:02:24.000 | 2022-09-01 00:09:39.000 |             1.0 |          1.32 |        1.0 | N                  |          238 |          1>
        2 | 2022-09-01 00:47:25.000 | 2022-09-01 00:56:09.000 |             1.0 |          2.94 |        1.0 | N                  |
```

#### 清理 Hive 资源

1. 使用 `exit` 命令退出 Trino CLI。

2. 从 `examples` 目录运行清理脚本以删除从 hive 脚本创建的所有资源：

```
cd data-on-eks/distributed-databases/trino/examples
./hive-cleanup.sh
```

### 示例 #2：使用 Iceberg 连接器

在此示例中，我们将使用 Apache Iceberg 与 AWS Glue 作为目录类型进行设置，并将数据以 PARQUET 格式存储在 Amazon S3 中。

在 EKS 上使用 Trino 与 Iceberg 连接器，我们将使用 Trino CLI 创建上述资源并运行示例 SQL 查询来插入和检索数据。

#### 运行查询

- 让我们找出蓝图创建的 S3 数据存储桶。我们将使用此存储桶以 PARQUET 格式在 Iceberg 表中存储数据。
```bash
cd data-on-eks/distributed-databases/trino
export BUCKET=$(terraform output --state="./terraform.tfstate" --raw data_bucket)
echo $BUCKET
```
- 让我们现在创建一个 Iceberg 模式，其中包含从 [TPCDS](https://trino.io/docs/current/connector/tpcds.html) 的 sf10000 模式表填充数据的表。我们将使用 CREATE TABLE AS SELECT (CTAS) 语句。SQL 文件 `examples/trino_sf10000_tpcds_to_iceberg.sql` 包含以下 SQL 语句：

```bash
use tpcds.sf10000;
select * from tpcds.sf10000.item limit 10;
select * from tpcds.sf10000.warehouse limit 10;

/* Drop tables & schema */

drop schema iceberg.iceberg_schema;
drop table iceberg.iceberg_schema.warehouse;
drop table iceberg.iceberg_schema.item;
drop table iceberg.iceberg_schema.inventory;
drop table iceberg.iceberg_schema.date_dim;

/* Iceberg schema creation */

create schema if not exists iceberg.iceberg_schema
with (LOCATION = 's3://trino-data-bucket-20240215180855515400000001/iceberg/');

/* Iceberg Table Creation with CTAS from tpcds tables */

create table if not exists iceberg.iceberg_schema.inventory
with (FORMAT = 'PARQUET')
as select *
from tpcds.sf10000.inventory;

create table if not exists iceberg.iceberg_schema.date_dim
with (FORMAT = 'PARQUET')
as select d_date_sk,
cast(d_date_id as varchar(16)) as d_date_id,
d_date,
d_month_seq,
d_week_seq,
d_quarter_seq,
d_year,
d_dow,
d_moy,
d_dom,
d_qoy,
d_fy_year,
d_fy_quarter_seq,
d_fy_week_seq,
cast(d_day_name as varchar(9)) as d_day_name,
cast(d_quarter_name as varchar(6)) as d_quarter_name,
cast(d_holiday as varchar(1)) as d_holiday,
cast(d_weekend as varchar(1)) as d_weekend,
cast(d_following_holiday as varchar(1)) as d_following_holiday,
d_first_dom,
d_last_dom,
d_same_day_ly,
d_same_day_lq,
cast(d_current_day as varchar(1)) as d_current_day,
cast(d_current_week as varchar(1)) as d_current_week,
cast(d_current_month as varchar(1)) as d_current_month,
cast(d_current_quarter as varchar(1)) as d_current_quarter
from tpcds.sf10000.date_dim;

create table if not exists iceberg.iceberg_schema.warehouse
with (FORMAT = 'PARQUET')
as select
w_warehouse_sk,
cast(w_warehouse_id as varchar(16)) as w_warehouse_id,
w_warehouse_name,
w_warehouse_sq_ft,
cast(w_street_number as varchar(10)) as w_street_number,
w_street_name,
cast(w_street_type as varchar(15)) as w_street_type,
cast(w_suite_number as varchar(10)) as w_suite_number,
w_city,
w_county,
cast(w_state as varchar(2)) as w_state,
cast(w_zip as varchar(10)) as w_zip,
w_country,
w_gmt_offset
from tpcds.sf10000.warehouse;

create table if not exists iceberg.iceberg_schema.item
with (FORMAT = 'PARQUET')
as select
i_item_sk,
cast(i_item_id as varchar(16)) as i_item_id,
i_rec_start_date,
i_rec_end_date,
i_item_desc,
i_current_price,
i_wholesale_cost,
i_brand_id,
cast(i_brand as varchar(50)) as i_brand,
i_class_id,
cast(i_class as varchar(50)) as i_class,
i_category_id,
cast(i_category as varchar(50)) as i_category,
i_manufact_id,
cast(i_manufact as varchar(50)) as i_manufact,
cast(i_size as varchar(50)) as i_size,
cast(i_formulation as varchar(20)) as i_formulation,
cast(i_color as varchar(20)) as i_color,
cast(i_units as varchar(10)) as i_units,
cast(i_container as varchar(10)) as i_container,
i_manager_id,
cast(i_product_name as varchar(50)) as i_product_name
from tpcds.sf10000.item;


/* Select from Iceberg table */

select * from iceberg.iceberg_schema.date_dim limit 10;
select * from iceberg.iceberg_schema.item limit 10;
select * from iceberg.iceberg_schema.inventory limit 10;

/* Running query from Iceberg table */

with inv as
(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
,stdev,mean, case mean when 0 then null else stdev/mean end cov
from(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
,stddev_samp(inv_quantity_on_hand) stdev,avg(inv_quantity_on_hand) mean
from iceberg.iceberg_schema.inventory
,iceberg.iceberg_schema.item
,iceberg.iceberg_schema.warehouse
,iceberg.iceberg_schema.date_dim
where inv_item_sk = i_item_sk
and inv_warehouse_sk = w_warehouse_sk
and inv_date_sk = d_date_sk
and d_year =1999
group by w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy) foo
where case mean when 0 then 0 else stdev/mean end > 1)
select inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean, inv1.cov
,inv2.w_warehouse_sk,inv2.i_item_sk,inv2.d_moy,inv2.mean, inv2.cov
from inv inv1,inv inv2
where inv1.i_item_sk = inv2.i_item_sk
and inv1.w_warehouse_sk = inv2.w_warehouse_sk
and inv1.d_moy=4
and inv2.d_moy=4+1
and inv1.cov > 1.5
order by inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean,inv1.cov,inv2.d_moy,inv2.mean, inv2.cov;
```

- 上述 SQL 命令将执行以下操作：
    - 创建名为 `iceberg_schema` 的 Iceberg 模式
    - 创建 4 个 Iceberg 表 - `warehouse`、`item`、`inventory` 和 `date_dim`，数据来自 tpcds 的相同表
    - 从上述 Iceberg 表查询数据

- 让我们现在使用 Trino CLI 执行上述 SQL 命令：
```bash
envsubst < examples/trino_sf10000_tpcds_to_iceberg.sql > examples/iceberg.sql
./trino --file 'examples/iceberg.sql' --server http://localhost:8080 --user admin --ignore-errors
```

- 您可以在 Trino UI Web 监视器中看到已完成和正在运行的 SQL 查询，如下所示：


![Trino 查询](../../../../../../docs/blueprints/distributed-databases/img/trino-queries.PNG)

- 让我们打开另一个终端，看看当上述 SQL 命令运行时，KEDA 如何扩展 Trino worker Pod：
```bash
kubectl get hpa -n trino -w
```
#### 输出
```bash
NAME                                REFERENCE                 TARGETS                MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   <unknown>/1, <unknown>/1 + 1 more...   1         15        0          37m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 1/1 + 1 more...                   1         15        1          38m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 500m/1 + 1 more...                1         15        1          40m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 0/1 + 1 more...                   1         15        1          40m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 0/1 + 1 more...                   1         15        1          40m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 0/1 + 1 more...                   1         15        1          40m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 0/1 + 1 more...                   1         15        2          41m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 0/1 + 1 more...                   1         15        2          41m
keda-hpa-keda-scaler-trino-worker   Deployment/trino-worker   0/1, 0/1 + 1 more...                   1         15        2          41m
```
您可以看到 HPA 随着查询负载增加和 worker 平均 CPU 利用率从初始 0 个 worker 扩展到 2 个 worker：

![Trino Scaling](../../../../../../docs/blueprints/distributed-databases/img/trino-workers-scaling.png)

### 示例 #3（可选）：Trino 中的容错执行
[容错执行](https://trino.io/docs/current/admin/fault-tolerant-execution.html)是 Trino 中的一个选择性机制，使用 [Project Tardigrade](https://trino.io/blog/2022/05/05/tardigrade-launch.html#what-is-project-tardigrade) 实现。没有容错配置时，当查询的任何组件任务由于任何原因失败时（例如，worker 节点故障或终止），Trino 查询就会失败。这些失败的查询必须从头重新启动，导致执行时间更长、计算浪费和支出，特别是对于长时间运行的查询。

当在 Trino 中配置容错执行和[重试策略](https://trino.io/docs/current/admin/fault-tolerant-execution.html#retry-policy)时，中间交换数据会使用[交换管理器](https://trino.io/docs/current/admin/fault-tolerant-execution.html#exchange-manager)在外部存储（如 Amazon S3 或 HDFS）中进行缓冲。然后 Trino 重试失败的查询（如果重试策略配置为"QUERY"）或失败的任务（如果重试策略配置为"TASK"）。在查询执行期间发生 worker 中断或其他故障时，Trino 的其余 worker 重用交换管理器数据来重试并完成查询。
:::info
**QUERY 重试策略**指示 Trino 在 worker 节点发生错误时重试整个查询。当 Trino 集群的大部分工作负载包含许多小查询时，建议使用此重试策略。

**TASK 重试策略**指示 Trino 在发生故障时重试单个任务。当 Trino 执行大型批处理查询时，建议使用此策略。集群可以更有效地重试查询中的较小任务，而不是重试整个查询。
:::
- 此蓝图已在 coordinator 和 worker Pod 的 **`config.properties`** 文件中使用 `TASK` 重试策略部署了具有容错配置的 Trino 集群。让我们通过在 coordinator Pod 内打开 bash 命令 shell 来验证：
```bash
COORDINATOR_POD=$(kubectl get pods -l "app.kubernetes.io/instance=trino,app.kubernetes.io/component=coordinator" -o name -n trino)
kubectl exec --stdin --tty $COORDINATOR_POD -n trino -- /bin/bash
cat /etc/trino/config.properties
```
#### 输出
```bash
coordinator=true
node-scheduler.include-coordinator=false
http-server.http.port=8080
query.max-memory=280GB
query.max-memory-per-node=22GB
discovery.uri=http://localhost:8080
retry-policy=TASK
exchange.compression-enabled=true
query.low-memory-killer.delay=0s
query.remote-task.max-error-duration=1m
query.hash-partition-count=50
```
- 蓝图还在 coordinator 和 worker Pod 的 **`exchange-manager.properties`** 文件中使用 Amazon S3 存储桶配置了交换管理器。让我们也在 coordinator Pod 内验证：
```bash
cat /etc/trino/exchange-manager.properties
```
#### 输出
```bash
exchange-manager.name=filesystem
exchange.base-directories=s3://trino-exchange-bucket-20240215180855570800000004
exchange.s3.region=us-west-2
exchange.s3.iam-role=arn:aws:iam::xxxxxxxxxx:role/trino-sa-role
```
请记下上面的交换管理器 S3 存储桶名称。您可以在 AWS 控制台中探索上述 S3 存储桶的内容。当没有查询运行时，它将为空。
- 现在，让我们退出 coordinator Pod 的 bash shell
```bash
exit
```

通过以下步骤，我们现在将通过运行 `select` 查询并在查询仍在运行时终止几个 Trino worker 来测试容错执行。
- 在 `examples` 文件夹中找到文件 `trino_select_query_iceberg.sql`，其中包含以下 SQL 命令：
```bash
with inv as
(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
,stdev,mean, case mean when 0 then null else stdev/mean end cov
from(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
,stddev_samp(inv_quantity_on_hand) stdev,avg(inv_quantity_on_hand) mean
from iceberg.iceberg_schema.inventory
,iceberg.iceberg_schema.item
,iceberg.iceberg_schema.warehouse
,iceberg.iceberg_schema.date_dim
where inv_item_sk = i_item_sk
and inv_warehouse_sk = w_warehouse_sk
and inv_date_sk = d_date_sk
and d_year =1999
group by w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy) foo
where case mean when 0 then 0 else stdev/mean end > 1)
select inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean, inv1.cov
,inv2.w_warehouse_sk,inv2.i_item_sk,inv2.d_moy,inv2.mean, inv2.cov
from inv inv1,inv inv2
where inv1.i_item_sk = inv2.i_item_sk
and inv1.w_warehouse_sk = inv2.w_warehouse_sk
and inv1.d_moy=4
and inv2.d_moy=4+1
and inv1.cov > 1.5
order by inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean,inv1.cov,inv2.d_moy,inv2.mean, inv2.cov;
```
- 让我们现在首先运行 select 查询
```bash
./trino --file 'examples/trino_select_query_iceberg.sql' --server http://localhost:8080 --user admin --ignore-errors
```
- 在上述命令之后立即，当上述查询仍在运行时，打开另一个终端并将 worker Pod 缩减到只有 1 个 worker，使用以下命令终止所有其他 worker：
```bash
kubectl scale deployment trino-worker -n trino --replicas=1
```
在浏览器中查看 Trino Web UI，现在只有 1 个活动 worker 在运行，因为其他 worker 已被终止：

![终止的 worker](../../../../../../docs/blueprints/distributed-databases/img/trino-ft-terminated-workers.png)

- 转到 Amazon S3 控制台并验证交换管理器 S3 存储桶中的中间交换数据缓冲，存储桶名称以 `trino-exchange-bucket` 开头。

![交换管理器](../../../../../../docs/blueprints/distributed-databases/img/trino-exchange-manager.png)

- 让我们现在再次查看 Trino Web UI 监视器，以验证尽管由于终止的 worker 导致 6 个任务失败（我们在下面的屏幕截图中用红色圈出了它们），查询仍然完成。

:::info
请注意，根据在被终止的 worker 上运行的任务数量，您的 Trino Web UI 中失败任务的数量可能不同。

另外，根据使用 CPU 利用率指标的水平 Pod 自动扩展器（HPA）扩展的 worker Pod，您可以看到不同数量的活动 worker
:::

![Trino 查询完成](../../../../../../docs/blueprints/distributed-databases/img/trino-ft-query-completion.png)

#### 清理 Iceberg 资源

1. 让我们打开 Trino CLI
```bash
./trino http://127.0.0.1:8080 --user admin
```

2. 现在，让我们通过在 Trino CLI 上运行以下 SQL 命令来删除 Iceberg 表和模式：
 ```bash
drop table iceberg.iceberg_schema.warehouse;
drop table iceberg.iceberg_schema.item;
drop table iceberg.iceberg_schema.inventory;
drop table iceberg.iceberg_schema.date_dim;
drop schema iceberg.iceberg_schema;
```
3. 使用 `exit` 命令退出 Trino CLI。

## 清理 🧹

要删除作为此蓝图一部分配置的所有组件，请使用以下命令销毁所有资源。

```bash
cd data-on-eks/distributed-databases/trino
./cleanup.sh
```

:::caution

为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源

例如：Trino 交换管理器的 S3 存储桶
:::

## 结论

Trino 是一个用于从数据源快速查询大量数据的工具。在此示例中，我们分享了一个基于 terraform 的蓝图，该蓝图在 Amazon EKS 上部署具有容错配置的 Trino，以及构建完整 EKS 集群所需的插件（即用于节点自动扩展的 Karpenter、用于 Trino worker Pod 自动扩展的 Metrics server 和 HPA、使用 Prometheus/Grafana 堆栈进行监控）。在众多功能中，我们重点介绍了使用 Amazon S3 作为存储创建 Iceberg 或 Hive 数据存储以及运行简单 Trino 查询获取结果的几个示例。我们还在 Spot 实例上部署和扩展了 Trino worker 以进行成本优化。我们还演示了 Trino 的容错功能，这使其适合 Spot 实例为长时间运行的批处理查询节省成本。
