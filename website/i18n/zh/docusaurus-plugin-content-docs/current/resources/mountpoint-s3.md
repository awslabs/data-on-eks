---
sidebar_position: 2
sidebar_label: EKS 上的 Mountpoint-S3
---

# Mountpoint S3：增强 Amazon EKS 上数据和 AI 工作负载的 Amazon S3 文件访问

## 什么是 Mountpoint-S3？

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) 是 AWS 开发的开源文件客户端，它将文件操作转换为 S3 API 调用，使您的应用程序能够像访问本地磁盘一样与 [Amazon S3](https://aws.amazon.com/s3/) 存储桶交互。Mountpoint for Amazon S3 针对需要对大对象进行高读取吞吐量的应用程序进行了优化，可能同时来自多个客户端，并且一次从单个客户端顺序写入新对象。与传统的 S3 访问方法相比，它提供了显著的性能提升，使其成为数据密集型工作负载和 AI/ML 训练的理想选择。

Mountpoint-S3 的一个关键功能是它与 [Amazon S3 标准](https://aws.amazon.com/s3/storage-classes/) 和 [Amazon S3 Express One Zone](https://aws.amazon.com/s3/storage-classes/) 的兼容性。S3 Express One Zone 是专为*单可用区部署*设计的高性能存储类。它提供一致的个位数毫秒数据访问，使其成为频繁访问数据和延迟敏感应用程序的理想选择。S3 Express One Zone 以提供比 S3 标准快 10 倍的数据访问速度和低 50% 的请求成本而闻名。此存储类使用户能够在同一可用区中共同定位存储和计算资源，优化性能并可能降低计算成本。

与 S3 Express One Zone 的集成增强了 Mountpoint-S3 的功能，特别是对于机器学习和分析工作负载，因为它可以与 [Amazon EKS](https://aws.amazon.com/eks/)、[Amazon SageMaker 模型训练](https://aws.amazon.com/sagemaker/train/)、[Amazon Athena](https://aws.amazon.com/athena/)、[Amazon EMR](https://aws.amazon.com/emr/) 和 [AWS Glue 数据目录](https://docs.aws.amazon.com/prescriptive-guidance/latest/serverless-etl-aws-glue/aws-glue-data-catalog.html) 等服务一起使用。S3 Express One Zone 中基于消费的存储自动扩展简化了低延迟工作负载的管理，使 Mountpoint-S3 成为广泛数据密集型任务和 AI/ML 训练环境的高效工具。

:::warning

Mountpoint-S3 不支持文件重命名操作，这可能会限制其在需要此类功能的场景中的适用性。

:::

## 在 Amazon EKS 上部署 Mountpoint-S3：

### 步骤 1：为 S3 CSI 驱动程序设置 IAM 角色

使用 Terraform 创建具有 S3 CSI 驱动程序必要权限的 IAM 角色。此步骤对于确保 EKS 和 S3 之间的安全高效通信至关重要。

```terraform

#---------------------------------------------------------------
# IRSA for Mountpoint for Amazon S3 CSI Driver
#---------------------------------------------------------------
module "s3_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.34"
  role_name_prefix      = format("%s-%s-", local.name, "s3-csi-driver")
  role_policy_arns = {
    # WARNING: Demo purpose only. Bring your own IAM policy with least privileges
    s3_csi_driver = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:s3-csi-driver-sa"]
    }
  }
  tags = local.tags
