---
sidebar_position: 2
sidebar_label: EKS 上的 Mountpoint-S3
---

# Mountpoint S3：增强 Amazon EKS 上数据和 AI 工作负载的 Amazon S3 文件访问

## 什么是 Mountpoint-S3？

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) 是 AWS 开发的开源文件客户端，它将文件操作转换为 S3 API 调用，使您的应用程序能够像访问本地磁盘一样与 [Amazon S3](https://aws.amazon.com/s3/) 存储桶交互。Mountpoint for Amazon S3 针对需要对大型对象进行高读取吞吐量的应用程序进行了优化，可能同时来自多个客户端，并且一次从单个客户端顺序写入新对象。与传统的 S3 访问方法相比，它提供了显著的性能提升，使其成为数据密集型工作负载和 AI/ML 训练的理想选择。

Mountpoint-S3 的一个关键特性是它与 [Amazon S3 Standard](https://aws.amazon.com/s3/storage-classes/) 和 [Amazon S3 Express One Zone](https://aws.amazon.com/s3/storage-classes/) 的兼容性。S3 Express One Zone 是专为*单可用区部署*设计的高性能存储类。它提供一致的个位数毫秒数据访问，使其成为频繁访问数据和延迟敏感应用程序的理想选择。S3 Express One Zone 以提供比 S3 Standard 快 10 倍的数据访问速度和低 50% 的请求成本而闻名。此存储类使用户能够在同一可用区中共同定位存储和计算资源，优化性能并可能降低计算成本。

与 S3 Express One Zone 的集成增强了 Mountpoint-S3 的功能，特别是对于机器学习和分析工作负载，因为它可以与 [Amazon EKS](https://aws.amazon.com/eks/)、[Amazon SageMaker Model Training](https://aws.amazon.com/sagemaker/train/)、[Amazon Athena](https://aws.amazon.com/athena/)、[Amazon EMR](https://aws.amazon.com/emr/) 和 [AWS Glue Data Catalog](https://docs.aws.amazon.com/prescriptive-guidance/latest/serverless-etl-aws-glue/aws-glue-data-catalog.html) 等服务一起使用。S3 Express One Zone 中基于消耗的存储自动扩展简化了低延迟工作负载的管理，使 Mountpoint-S3 成为广泛数据密集型任务和 AI/ML 训练环境的高效工具。

:::warning

Mountpoint-S3 不支持文件重命名操作，这可能会限制其在需要此类功能的场景中的适用性。

:::

## 在 Amazon EKS 上部署 Mountpoint-S3：

### 步骤 1：为 S3 CSI Driver 设置 IAM 角色

使用 Terraform 创建具有 S3 CSI driver 必要权限的 IAM 角色。此步骤对于确保 EKS 和 S3 之间的安全高效通信至关重要。

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
}

```

### 步骤 2：配置 EKS Blueprints Addons

配置 EKS Blueprints Addons Terraform 模块以利用此角色用于 S3 CSI driver 的 Amazon EKS Add-on。

```terraform
#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.s3_csi_driver_irsa.iam_role_arn
    }
  }
}

```

### 步骤 3：定义 PersistentVolume

在 PersistentVolume (PV) 配置中指定 S3 存储桶、区域详细信息和访问模式。此步骤对于定义 EKS 如何与 S3 存储桶交互至关重要。

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-pv
spec:
  capacity:
    storage: 1200Gi # ignored, required
  accessModes:
    - ReadWriteMany # supported options: ReadWriteMany / ReadOnlyMany
  mountOptions:
    - uid=1000
    - gid=2000
    - allow-other
    - allow-delete
    - region <ENTER_REGION>
  csi:
    driver: s3.csi.aws.com # required
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: <ENTER_S3_BUCKET_NAME>
```

### 步骤 4：创建 PersistentVolumeClaim

建立 PersistentVolumeClaim (PVC) 以利用定义的 PV，指定访问模式和静态配置要求。

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-claim
  namespace: spark-team-a
spec:
  accessModes:
    - ReadWriteMany # supported options: ReadWriteMany / ReadOnlyMany
  storageClassName: "" # required for static provisioning
  resources:
    requests:
      storage: 1200Gi # ignored, required
  volumeName: s3-pv

```

### 步骤 5：在 Pod 定义中使用 PVC
设置 PersistentVolumeClaim (PVC) 后，下一步是在 Pod 定义中使用它。这允许在 Kubernetes 中运行的应用程序访问存储在 S3 存储桶中的数据。以下示例演示了如何在不同场景的 Pod 定义中引用 PVC。

#### 示例 1：使用 PVC 进行存储的基本 Pod

此示例显示了将 `s3-claim` PVC 挂载到容器内目录的基本 Pod 定义。

在此示例中，PVC `s3-claim` 挂载到 nginx 容器的 `/data` 目录。此设置允许在容器内运行的应用程序像访问本地目录一样读取和写入 S3 存储桶中的数据。

```yaml

apiVersion: v1
kind: Pod
metadata:
  name: example-pod
  namespace: spark-team-a
spec:
  containers:
    - name: app-container
      image: nginx  # Example image
      volumeMounts:
        - name: s3-storage
          mountPath: "/data"  # The path where the S3 bucket will be mounted
  volumes:
    - name: s3-storage
      persistentVolumeClaim:
        claimName: s3-claim

```

#### 示例 2：使用 PVC 的 AI/ML 训练作业

在 AI/ML 训练场景中，数据可访问性和吞吐量至关重要。此示例演示了访问存储在 S3 中的数据集的机器学习训练作业的 Pod 配置。

```yaml

apiVersion: v1
kind: Pod
metadata:
  name: ml-training-pod
  namespace: spark-team-a
spec:
  containers:
    - name: training-container
      image: ml-training-image  # Replace with your ML training image
      volumeMounts:
        - name: dataset-storage
          mountPath: "/datasets"  # Mount path for training data
  volumes:
    - name: dataset-storage
      persistentVolumeClaim:
        claimName: s3-claim

```

:::warning

当与 Amazon S3 或 S3 express 一起使用时，Mountpoint S3 可能不适合作为 Spark 工作负载的 shuffle 存储。此限制是由于 Spark 中 shuffle 操作的性质，这些操作通常涉及多个客户端同时读取和写入同一位置。

此外，Mountpoint S3 不支持文件重命名，这是 Spark 中高效 shuffle 操作所需的关键功能。缺乏重命名功能可能导致操作挑战和数据处理任务中的潜在性能瓶颈。

:::

## 下一步：

- 探索提供的 Terraform 代码片段以获取详细的部署说明。
- 参考官方 Mountpoint-S3 文档以获取更多配置选项和限制。
- 利用 Mountpoint-S3 在您的 EKS 应用程序中解锁高性能、可扩展的 S3 访问。

通过了解 Mountpoint-S3 的功能和限制，您可以做出明智的决策来优化 Amazon EKS 上的数据驱动工作负载。
