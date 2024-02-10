---
sidebar_position: 2
sidebar_label: Mounpoint-S3 on EKS
---

# Mounpoint S3: Enhancing Amazon S3 File Access for Data & AI Workloads on Amazon EKS

## What is Mountpoint-S3?

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) is an open-source file client developed by AWS that translates file operations into S3 API calls, enabling your applications to interact with [Amazon S3](https://aws.amazon.com/s3/) buckets as if they were local disks. Mountpoint for Amazon S3 is optimized for applications that need high read throughput to large objects, potentially from many clients at once, and to write new objects sequentially from a single client at a time. It offers significant performance gains compared to traditional S3 access methods, making it ideal for data-intensive workloads and AI/ML training.

A key feature of Mountpoint-S3 is its compatibility with both [Amazon S3 Standrad](https://aws.amazon.com/s3/storage-classes/) and [Amazon S3 Express One Zone](https://aws.amazon.com/s3/storage-classes/). S3 Express One Zone is a high-performance storage class designed for *single-Availability Zone deployment*. It offers consistent single-digit millisecond data access, making it ideal for frequently accessed data and latency-sensitive applications. S3 Express One Zone is known for delivering data access speeds up to 10 times faster and at up to 50% lower request costs compared to S3 Standard. This storage class enables users to co-locate storage and compute resources in the same Availability Zone, optimizing performance and potentially reducing compute costs.

The integration with S3 Express One Zone enhances Mountpoint-S3's capabilities, particularly for machine learning and analytics workloads, as it can be used with services like [Amazon EKS](https://aws.amazon.com/eks/),  [Amazon SageMaker Model Training](https://aws.amazon.com/sagemaker/train/), [Amazon Athena](https://aws.amazon.com/athena/), [Amazon EMR](https://aws.amazon.com/emr/), and [AWS Glue Data Catalog](https://docs.aws.amazon.com/prescriptive-guidance/latest/serverless-etl-aws-glue/aws-glue-data-catalog.html). The automatic scaling of storage based on consumption in S3 Express One Zone simplifies management for low-latency workloads, making Mountpoint-S3 a highly effective tool for a wide range of data-intensive tasks and AI/ML training environments.


:::warning

Mountpoint-S3 does not support file renaming operations, which may limit its applicability in scenarios where such functionality is essential.

:::


## Deploying Mountpoint-S3 on Amazon EKS:

### Step 1: Set Up IAM Role for S3 CSI Driver

Create an IAM role using Terraform with the necessary permissions for the S3 CSI driver. This step is critical for ensuring secure and efficient communication between EKS and S3.


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

### Step 2: Configure EKS Blueprints Addons

Configure EKS Blueprints Addons Terraform module to utilize this role for the Amazon EKS Add-on of S3 CSI driver. 

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

### Step 3: Define a PersistentVolume

Specify the S3 bucket, region details and access modes in a PersistentVolume (PV) configuration. This step is crucial for defining how EKS interacts with the S3 bucket.

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

### Step 4: Create a PersistentVolumeClaim

Establish a PersistentVolumeClaim (PVC) to utilize the defined PV, specifying access modes and static provisioning requirements.

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

### Step 5: Using PVC with Pod Definition
After setting up the PersistentVolumeClaim (PVC), the next step is to utilize it within a Pod definition. This allows your applications running in Kubernetes to access the data stored in the S3 bucket. Below are examples demonstrating how to reference the PVC in a Pod definition for different scenarios.

#### Example 1: Basic Pod Using PVC for Storage

This example shows a basic Pod definition that mounts the `s3-claim` PVC to a directory within the container.

In this example, the PVC `s3-claim` is mounted to the `/data` directory of the nginx container. This setup allows the application running within the container to read and write data to the S3 bucket as if it were a local directory.

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

#### Example 2: AI/ML Training Job Using PVC

In AI/ML training scenarios, data accessibility and throughput are critical. This example demonstrates a Pod configuration for a machine learning training job that accesses datasets stored in S3.

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

Mountpoint S3, when used with Amazon S3 or S3 express, may not be suitable as a shuffle storage for Spark workloads. This limitation arises due to the nature of shuffle operations in Spark, which often involve multiple clients reading and writing to the same location simultaneously. 

Additionally, Mountpoint S3 does not support file renaming, a critical feature required for efficient shuffle operations in Spark. This lack of renaming capability can lead to operational challenges and potential performance bottlenecks in data processing tasks.

:::


## Next Steps:

- Explore the provided Terraform code snippet for detailed deployment instructions.
- Refer to the official Mountpoint-S3 documentation for further configuration options and limitations.
- Utilize Mountpoint-S3 to unlock high-performance, scalable S3 access within your EKS applications.

By understanding Mountpoint-S3's capabilities and limitations, you can make informed decisions to optimize your data-driven workloads on Amazon EKS.