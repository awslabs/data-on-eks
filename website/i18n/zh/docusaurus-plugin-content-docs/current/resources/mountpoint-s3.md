---
sidebar_position: 2
sidebar_label: EKS上的Mounpoint-S3
---

# Mounpoint S3：增强Amazon EKS上数据和AI工作负载的Amazon S3文件访问

## 什么是Mountpoint-S3？

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)是由AWS开发的开源文件客户端，它将文件操作转换为S3 API调用，使您的应用程序能够与[Amazon S3](https://aws.amazon.com/s3/)存储桶交互，就像它们是本地磁盘一样。Mountpoint for Amazon S3针对需要对大型对象进行高读取吞吐量的应用程序进行了优化，这些应用程序可能同时来自多个客户端，并且可以一次从单个客户端顺序写入新对象。与传统的S3访问方法相比，它提供了显著的性能提升，使其非常适合数据密集型工作负载和AI/ML训练。

Mountpoint-S3的一个关键特性是它与[Amazon S3 Standard](https://aws.amazon.com/s3/storage-classes/)和[Amazon S3 Express One Zone](https://aws.amazon.com/s3/storage-classes/)的兼容性。S3 Express One Zone是一种高性能存储类，专为*单可用区部署*设计。它提供一致的个位数毫秒数据访问，非常适合频繁访问的数据和对延迟敏感的应用程序。S3 Express One Zone以提供比S3 Standard快10倍的数据访问速度和高达50%的请求成本降低而闻名。此存储类使用户能够将存储和计算资源共同定位在同一可用区中，优化性能并可能降低计算成本。

与S3 Express One Zone的集成增强了Mountpoint-S3的功能，特别是对于机器学习和分析工作负载，因为它可以与[Amazon EKS](https://aws.amazon.com/eks/)、[Amazon SageMaker Model Training](https://aws.amazon.com/sagemaker/train/)、[Amazon Athena](https://aws.amazon.com/athena/)、[Amazon EMR](https://aws.amazon.com/emr/)和[AWS Glue Data Catalog](https://docs.aws.amazon.com/prescriptive-guidance/latest/serverless-etl-aws-glue/aws-glue-data-catalog.html)等服务一起使用。S3 Express One Zone中基于消费的存储自动扩展简化了低延迟工作负载的管理，使Mountpoint-S3成为广泛数据密集型任务和AI/ML训练环境的高效工具。


:::warning

Mountpoint-S3不支持文件重命名操作，这可能会限制其在需要此类功能的场景中的适用性。

:::


## 在Amazon EKS上部署Mountpoint-S3：

### 步骤1：为S3 CSI驱动程序设置IAM角色

使用Terraform创建具有S3 CSI驱动程序所需权限的IAM角色。这一步对于确保EKS和S3之间的安全高效通信至关重要。

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

### 步骤2：配置EKS Blueprints附加组件

配置EKS Blueprints附加组件Terraform模块，以利用此角色作为S3 CSI驱动程序的Amazon EKS附加组件。

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

### 步骤3：定义持久卷

在持久卷(PV)配置中指定S3存储桶、区域详细信息和访问模式。这一步对于定义EKS如何与S3存储桶交互至关重要。

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-pv
spec:
  capacity:
    storage: 1200Gi # 忽略，必需
  accessModes:
    - ReadWriteMany # 支持的选项：ReadWriteMany / ReadOnlyMany
  mountOptions:
    - uid=1000
    - gid=2000
    - allow-other
    - allow-delete
    - region <输入区域>
  csi:
    driver: s3.csi.aws.com # 必需
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: <输入S3存储桶名称>
```

### 步骤4：创建持久卷声明

建立持久卷声明(PVC)以利用定义的PV，指定访问模式和静态配置要求。

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-claim
  namespace: spark-team-a
spec:
  accessModes:
    - ReadWriteMany # 支持的选项：ReadWriteMany / ReadOnlyMany
  storageClassName: "" # 静态配置需要
  resources:
    requests:
      storage: 1200Gi # 忽略，必需
  volumeName: s3-pv

```
### 步骤5：在Pod定义中使用PVC
设置持久卷声明(PVC)后，下一步是在Pod定义中使用它。这允许在Kubernetes中运行的应用程序访问存储在S3存储桶中的数据。以下是示例，演示如何在不同场景的Pod定义中引用PVC。

#### 示例1：使用PVC进行存储的基本Pod

此示例显示了一个基本Pod定义，它将`s3-claim` PVC挂载到容器内的目录。

在此示例中，PVC `s3-claim`被挂载到nginx容器的`/data`目录。此设置允许容器内运行的应用程序读取和写入S3存储桶中的数据，就像它是本地目录一样。

```yaml

apiVersion: v1
kind: Pod
metadata:
  name: example-pod
  namespace: spark-team-a
spec:
  containers:
    - name: app-container
      image: nginx  # 示例镜像
      volumeMounts:
        - name: s3-storage
          mountPath: "/data"  # S3存储桶将被挂载的路径
  volumes:
    - name: s3-storage
      persistentVolumeClaim:
        claimName: s3-claim

```

#### 示例2：使用PVC的AI/ML训练作业

在AI/ML训练场景中，数据可访问性和吞吐量至关重要。此示例演示了一个Pod配置，用于访问存储在S3中的数据集的机器学习训练作业。

```yaml

apiVersion: v1
kind: Pod
metadata:
  name: ml-training-pod
  namespace: spark-team-a
spec:
  containers:
    - name: training-container
      image: ml-training-image  # 替换为您的ML训练镜像
      volumeMounts:
        - name: dataset-storage
          mountPath: "/datasets"  # 训练数据的挂载路径
  volumes:
    - name: dataset-storage
      persistentVolumeClaim:
        claimName: s3-claim

```

:::warning

当与Amazon S3或S3 express一起使用时，Mountpoint S3可能不适合作为Spark工作负载的shuffle存储。这一限制是由于Spark中shuffle操作的性质，这些操作通常涉及多个客户端同时读取和写入同一位置。

此外，Mountpoint S3不支持文件重命名，这是Spark中高效shuffle操作所需的关键功能。这种缺乏重命名功能的情况可能导致数据处理任务中的操作挑战和潜在的性能瓶颈。

:::


## 下一步：

- 探索提供的Terraform代码片段，了解详细的部署说明。
- 参考官方Mountpoint-S3文档，了解更多配置选项和限制。
- 利用Mountpoint-S3在EKS应用程序中解锁高性能、可扩展的S3访问。

通过了解Mountpoint-S3的功能和限制，您可以做出明智的决策，优化Amazon EKS上的数据驱动工作负载。
