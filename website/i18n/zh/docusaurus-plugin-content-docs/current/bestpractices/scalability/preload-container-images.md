---
sidebar_label: 预加载容器镜像
sidebar_position: 1
---

import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# 使用 EBS 快照将容器镜像预加载到数据卷中

此模式的目的是通过在 Bottlerocket OS 的数据卷中缓存镜像来减少大型镜像容器的冷启动时间。

数据分析和机器学习工作负载通常需要大型容器镜像（通常以 GB 为单位），从 Amazon ECR 或其他镜像注册表拉取和提取可能需要几分钟时间。减少镜像拉取时间是提高启动这些容器速度的关键。

Bottlerocket OS 是 AWS 专门为运行容器而构建的基于 Linux 的开源操作系统。它有两个卷，一个 OS 卷和一个数据卷，后者用于存储工件和容器镜像。此示例将利用数据卷来拉取镜像并为以后使用拍摄快照。

为了演示在 EBS 快照中缓存镜像并在 EKS 集群中启动它们的过程，此示例将使用 Amazon EKS 优化的 Bottlerocket AMI。

有关详细信息，请参阅 GitHub 示例和博客文章：
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
