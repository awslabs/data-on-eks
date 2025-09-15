---
sidebar_label: 预加载容器镜像
sidebar_position: 1
---

import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# 使用 EBS 快照将容器镜像预加载到数据卷中

此模式的目的是通过在 Bottlerocket OS 的数据卷中缓存镜像来减少大型镜像容器的冷启动时间。

数据分析和机器学习工作负载通常需要大型容器镜像（通常以 GB 为单位），从 Amazon ECR 或其他镜像注册表拉取和提取可能需要几分钟时间。减少镜像拉取时间是提高启动这些容器速度的关键。

Bottlerocket OS 是由 AWS 专门为运行容器而构建的基于 Linux 的开源操作系统。它有两个卷，一个 OS 卷和一个数据卷，后者用于存储工件和容器镜像。此示例将利用数据卷来拉取镜像并为以后使用创建快照。

为了演示在 EBS 快照中缓存镜像并在 EKS 集群中启动它们的过程，此示例将使用 Amazon EKS 优化的 Bottlerocket AMI。

有关详细信息，请参考 GitHub 示例和博客文章：
- [GitHub - 为 AWS Bottlerocket 实例缓存容器镜像](https://github.com/aws-samples/bottlerocket-images-cache/tree/main)
- [博客文章 - 使用 Bottlerocket 数据卷减少 Amazon EKS 上的容器启动时间](https://aws.amazon.com/blogs/containers/reduce-container-startup-time-on-amazon-eks-with-bottlerocket-data-volume/)

## 此脚本概述

![](../../../../../../docs/bestpractices/scalability/img/bottlerocket-image-cache.png)

1. 使用 Bottlerocket for EKS AMI 启动 EC2 实例。
2. 通过 Amazon System Manager 访问实例
3. 使用 Amazon System Manager Run Command 在此 EC2 中拉取要缓存的镜像。
4. 关闭实例，为数据卷构建 EBS 快照。
5. 终止实例。

## 使用示例

```
git clone https://github.com/aws-samples/bottlerocket-images-cache/
cd bottlerocket-images-cache/

# 在终端中使用 nohup 以避免断开连接
❯ nohup ./snapshot.sh --snapshot-size 150 -r us-west-2 \
  docker.io/rayproject/ray-ml:2.10.0-py310-gpu,public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest &

❯ tail -f nohup.out

2024-07-15 17:18:53 I - [1/8] Deploying EC2 CFN stack ...
2024-07-15 17:22:07 I - [2/8] Launching SSM .
2024-07-15 17:22:08 I - SSM launched in instance i-07d10182abc8a86e1.
2024-07-15 17:22:08 I - [3/8] Stopping kubelet.service ..
2024-07-15 17:22:10 I - Kubelet service stopped.
2024-07-15 17:22:10 I - [4/8] Cleanup existing images ..
2024-07-15 17:22:12 I - Existing images cleaned
2024-07-15 17:22:12 I - [5/8] Pulling images:
2024-07-15 17:22:12 I - Pulling docker.io/rayproject/ray-ml:2.10.0-py310-gpu - amd64 ...
2024-07-15 17:27:50 I - docker.io/rayproject/ray-ml:2.10.0-py310-gpu - amd64 pulled.
2024-07-15 17:27:50 I - Pulling docker.io/rayproject/ray-ml:2.10.0-py310-gpu - arm64 ...
2024-07-15 17:27:58 I - docker.io/rayproject/ray-ml:2.10.0-py310-gpu - arm64 pulled.
2024-07-15 17:27:58 I - Pulling public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - amd64 ...
2024-07-15 17:31:34 I - public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - amd64 pulled.
2024-07-15 17:31:34 I - Pulling public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - arm64 ...
2024-07-15 17:31:36 I - public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - arm64 pulled.
2024-07-15 17:31:36 I - [6/8] Stopping instance ...
2024-07-15 17:32:25 I - Instance i-07d10182abc8a86e1 stopped
2024-07-15 17:32:25 I - [7/8] Creating snapshot ...
2024-07-15 17:38:36 I - Snapshot snap-0c6d965cf431785ed generated.
2024-07-15 17:38:36 I - [8/8] Cleanup.
2024-07-15 17:38:37 I - Stack deleted.
2024-07-15 17:38:37 I - --------------------------------------------------
2024-07-15 17:38:37 I - All done! Created snapshot in us-west-2: snap-0c6d965cf431785ed
```

您可以复制快照 ID `snap-0c6d965cf431785ed` 并将其配置为 worker 节点的快照。

# 在 Amazon EKS 和 Karpenter 中使用快照

您可以在 Karpenter 节点类中指定 `snapshotID`。在 EC2NodeClass 上添加内容：

```
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: Bottlerocket # 确保 OS 是 BottleRocket
  blockDeviceMappings:
    - deviceName: /dev/xvdb
      ebs:
        volumeSize: 150Gi
        volumeType: gp3
        kmsKeyID: "arn:aws:kms:<REGION>:<ACCOUNT_ID>:key/1234abcd-12ab-34cd-56ef-1234567890ab" # 如果使用自定义 KMS 密钥，请指定 KMS ID
        snapshotID: snap-0123456789 # 在此处指定您的快照 ID
```

# 端到端部署示例

有关端到端部署示例，请参考上面链接的 GitHub 示例和文档，或探索此存储库中的各种数据分析蓝图。
