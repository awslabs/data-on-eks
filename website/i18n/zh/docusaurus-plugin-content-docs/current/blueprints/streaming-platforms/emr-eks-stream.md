---
title: EMR on EKS with Spark Streaming
sidebar_position: 2
---

:::danger
**弃用通知**

此蓝图将被弃用，并最终于 **2024 年 10 月 27 日** 从此 GitHub 存储库中删除。不会修复错误，也不会添加新功能。弃用的决定基于对此蓝图缺乏需求和兴趣，以及难以分配资源来维护一个没有任何用户或客户积极使用的蓝图。

如果您在生产中使用此蓝图，请将自己添加到 [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) 页面并在存储库中提出问题。这将帮助我们重新考虑并可能保留和继续维护蓝图。否则，您可以制作本地副本或使用现有标签来访问它。
:::

# EMR on EKS with Spark Streaming

这是一个用 Python [CDK](https://docs.aws.amazon.com/cdk/latest/guide/home.html) 开发的项目。
它包括示例数据、Kafka 生产者模拟器，以及可以在 EMR on EC2 或 EMR on EKS 上运行的消费者示例。此外，我们还为不同用例添加了一些 Kinesis 示例。

基础设施部署包括以下内容：
- 一个新的 S3 存储桶来存储示例数据和流作业代码
- 跨 2 个可用区的新 VPC 中的 EKS 集群 v1.24
    - 集群有 2 个默认托管节点组：按需节点组从 1 扩展到 5，SPOT 实例节点组可以从 1 扩展到 30。
    - 它还有一个标记为 `serverless` 值的 Fargate 配置文件
- 同一 VPC 中的 EMR 虚拟集群
    - 虚拟集群链接到 `emr` 命名空间
    - 命名空间容纳两种类型的 Spark 作业，即在托管节点组上运行或在 Fargate 上运行的无服务器作业
    - 所有 EMR on EKS 配置都已完成，包括通过 AWS 原生解决方案 IAM 角色为服务账户提供的 Pod 细粒度访问控制
- 同一 VPC 中的 MSK 集群，总共有 2 个代理。Kafka 版本是 2.8.1
    - Cloud9 IDE 作为演示中的命令行环境。
    - Kafka 客户端工具将安装在 Cloud9 IDE 上
- 启用托管扩展的 EMR on EC2 集群。
    - 1 个主节点和 1 个核心节点，使用 r5.xlarge。
    - 配置为一次运行一个 Spark 作业。
    - 可以从 1 扩展到 10 个核心 + 任务节点
    - 挂载 EFS 用于检查点测试/演示（引导操作）

## Spark 示例 - 从 MSK 读取流
从 Amazon MSK 读取的 Spark 消费者应用程序：

* [1. 使用 EMR on EKS 运行作业](#1-submit-a-job-with-emr-on-eks)
* [2. 在 EMR on EKS 上使用 Fargate 运行相同作业](#2-emr-on-eks-with-fargate)
* [3. 在 EMR on EC2 上运行相同作业](#3-optional-submit-step-to-emr-on-ec2)

## Spark 示例 - 从 Kinesis 读取流
* [1. （可选）构建自定义 docker 镜像](#1-optional-build-custom-docker-image)
* [2. 使用 kinesis-sql 连接器运行作业](#2-use-kinesis-sql-connector)
* [3. 使用 Spark 的 DStream 运行作业](#3-use-sparks-dstream)

## 部署基础设施
