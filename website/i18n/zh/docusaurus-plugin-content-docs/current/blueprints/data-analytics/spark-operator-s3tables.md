---
sidebar_position: 4
sidebar_label: S3 Tables with EKS
hide_table_of_contents: true
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

import TaxiTripExecute from '../../../../../../docs/blueprints/data-analytics/_taxi_trip_exec.md'
import ReplaceS3BucketPlaceholders from '../../../../../../docs/blueprints/data-analytics/_replace_s3_bucket_placeholders.mdx';

import CodeBlock from '@theme/CodeBlock';

# S3 Tables with Amazon EKS

![s3tables](../../../../../../docs/blueprints/data-analytics/img/s3tables.png)

## 什么是 S3 Tables？

Amazon S3 Tables 是一个完全托管的表格数据存储，专为优化性能、简化安全性并为大规模分析工作负载提供经济高效的存储而构建。它直接与 Amazon EMR、Amazon Athena、Amazon Redshift、AWS Glue 和 AWS Lake Formation 等服务集成，为运行分析和机器学习工作负载提供无缝体验。

## 为什么在 Amazon EKS 上运行 S3 Tables？

对于已经采用 Amazon EKS 进行 Spark 工作负载并使用 Iceberg 等表格式的用户，利用 S3 Tables 在性能、成本效率和安全控制方面提供优势。这种集成允许组织将 Kubernetes 原生功能与 S3 Tables 的功能相结合，可能在其现有环境中改善查询性能和资源扩展。通过遵循本文档中详述的步骤，用户可以将 S3 Tables 无缝集成到其 EKS 设置中，为分析工作负载提供灵活且互补的解决方案。

## S3 Tables 与 Iceberg 表格式的区别

虽然 S3 Tables 使用 Apache Iceberg 作为底层实现，但它们提供了专为 AWS 客户设计的增强功能：

- **🛠️ 自动压缩**：S3 Tables 实现自动压缩，通过将较小的文件组合成更大、更高效的文件，在后台智能优化数据存储。此过程降低存储成本，提高查询速度，并在无需手动干预的情况下持续运行。

- 🔄 **表维护**：它提供关键的维护任务，如快照管理和未引用文件删除。这种持续优化确保表保持高性能和成本效益，无需手动干预，减少运营开销，让团队专注于数据洞察。

- ❄️ **Apache Iceberg 支持**：提供对 Apache Iceberg 的内置支持，简化大规模数据湖管理，同时提高查询性能并降低成本。如果您想体验以下结果，请考虑为您的数据湖使用 S3 Tables。

- 🔒 **简化安全性**：S3 Tables 将您的表视为 AWS 资源，在表级别启用细粒度的 AWS Identity and Access Management (IAM) 权限。这简化了数据治理，增强了安全性，并使访问控制与您熟悉的 AWS 服务更加直观和可管理。

- ⚡ **增强性能**：Amazon S3 Tables 引入了一种新型存储桶，专为存储 Apache Iceberg 表而构建。与在通用 S3 存储桶中存储 Iceberg 表相比，表存储桶提供高达 3 倍的查询性能和高达 10 倍的每秒事务数。这种性能增强支持高频更新、实时摄取和更苛刻的工作负载，确保随着数据量增长的可扩展性和响应性。

- 🛠️ **与 AWS 服务集成**：S3 Tables 与 AWS 分析服务（如 Athena、Redshift、EMR 和 Glue）紧密集成，为分析工作负载提供原生支持。

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)中，您将配置使用开源 Spark Operator 和 Apache YuniKorn 运行 Spark 作业所需的以下资源。

此示例将运行 Spark K8s Operator 的 EKS 集群部署到新的 VPC 中。

</CollapsibleContent>
