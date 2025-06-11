---
sidebar_position: 1
sidebar_label: 介绍
---

# 作业调度器

作业调度器是许多组织基础设施的重要组成部分，有助于自动化和管理复杂的工作流程。当部署在Kubernetes上时，作业调度器可以利用平台的功能，如自动扩展、滚动更新和自我修复能力，以确保高可用性和可靠性。像**Apache Airflow**、**Argo Workflow**和**Amazon MWAA**这样的工具提供了一种简单高效的方式来管理和调度Kubernetes集群上的作业。

这些工具非常适合广泛的用例，包括数据管道、机器学习工作流和批处理。通过利用Kubernetes的强大功能，组织可以简化和自动化其作业调度器的管理，从而释放资源专注于业务的其他领域。随着其不断增长的工具生态系统和对广泛用例的支持，Kubernetes正成为在生产环境中运行作业调度器的越来越受欢迎的选择。
以下是与数据工作负载一起使用的最流行的作业调度工具。
本节提供了以下工具的部署模式和使用这些调度器触发Spark/ML作业的示例。

1. [Apache Airflow](https://airflow.apache.org/)
2. [Amazon Managed Workflows for Apache Airflow (MWAA)](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html)
3. [Argo Workflow](https://argoproj.github.io/workflows/)
4. [Prefect](https://www.prefect.io/)
5. [AWS Batch](https://aws.amazon.com/batch/)
