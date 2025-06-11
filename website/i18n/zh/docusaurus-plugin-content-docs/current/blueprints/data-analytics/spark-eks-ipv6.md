---
title: 在EKS上使用IPv6的Spark Operator
sidebar_position: 3
---

此示例展示了在IPv6模式下在Amazon EKS上运行的Spark Operator的使用。其目的是展示和演示在EKS IPv6集群上运行spark工作负载。

## 部署EKS集群及测试此示例所需的所有附加组件和基础设施

Terraform蓝图将配置在Amazon EKS IPv6上使用开源Spark Operator运行Spark作业所需的以下资源

* 一个具有3个私有子网和3个公共子网的双栈Amazon虚拟私有云(Amazon VPC)
* 公共子网的互联网网关、私有子网的NAT网关和仅出口互联网网关
* IPv6模式下的Amazon EKS集群(版本1.30)
* Amazon EKS核心托管节点组，用于托管我们将在集群上配置的一些附加组件
* 部署Spark-k8s-operator、Apache Yunikorn、Karpenter、Prometheus和Grafana服务器。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

在安装集群之前，创建一个EKS IPv6 CNI策略。按照链接中的说明操作：
[AmazonEKS_CNI_IPv6_Policy ](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy)

### 克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

### 初始化Terraform

导航到示例目录并运行初始化脚本`install.sh`。

```bash
cd ${DOEKS_HOME}/analytics//terraform/spark-eks-ipv6/
chmod +x install.sh
./install.sh
```

### 导出Terraform输出

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
export AWS_REGION=$(terraform output -raw region)
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_event_logs_example_data)
```

S3_BUCKET变量保存了安装期间创建的存储桶名称。此存储桶将在后续示例中用于存储输出数据。

### 更新kubeconfig

更新kubeconfig以验证部署。

```bash
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
```

### 验证部署

检查分配给集群节点和pod的IP地址。您会注意到两者都分配了IPv6地址。

```bash
kubectl get node -o custom-columns='NODE_NAME:.metadata.name,INTERNAL-IP:.status.addresses[?(@.type=="InternalIP")].address'
NODE_NAME                                 INTERNAL-IP
ip-10-1-0-212.us-west-2.compute.internal  2600:1f13:520:1303:c87:4a71:b9ea:417c
ip-10-1-26-137.us-west-2.compute.internal 2600:1f13:520:1304:15b2:b8a3:7f63:cbfa
ip-10-1-46-28.us-west-2.compute.internal  2600:1f13:520:1305:5ee5:b994:c0c2:e4da
```

```bash
kubectl get pods -A -o custom-columns='NAME:.metadata.name,NodeIP:.status.hostIP,PodIP:status.podIP'
NAME                                                     NodeIP                                  PodIP
....
karpenter-5fd95dffb8-l8j26                               2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::
karpenter-5fd95dffb8-qpv55                               2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:60ac::
kube-prometheus-stack-grafana-9f5c9d8fc-zgn98            2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::a
kube-prometheus-stack-kube-state-metrics-98c74d866-56275 2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::9
kube-prometheus-stack-operator-67df8bc57d-2d8jh          2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::b
kube-prometheus-stack-prometheus-node-exporter-5qrqs     2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:c87:4a71:b9ea:417c
kube-prometheus-stack-prometheus-node-exporter-hcpvk     2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:15b2:b8a3:7f63:cbfa
kube-prometheus-stack-prometheus-node-exporter-ztkdm     2600:1f13:520:1305:5ee5:b994:c0c2:e4da  2600:1f13:520:1305:5ee5:b994:c0c2:e4da
prometheus-kube-prometheus-stack-prometheus-0            2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::7
spark-history-server-6c9f9d7cc4-xzj4c                    2600:1f13:520:1305:5ee5:b994:c0c2:e4da  2600:1f13:520:1305:64b::1
spark-operator-84c6b48ffc-z2glj                          2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::5
spark-operator-webhook-init-kbl4s                        2600:1f13:520:1305:5ee5:b994:c0c2:e4da  2600:1f13:520:1305:64b::2
yunikorn-admission-controller-d675f89c5-f2p47            2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:c87:4a71:b9ea:417c
yunikorn-scheduler-59d6879975-2rh4d                      2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::4
....
```

### 使用Karpenter执行示例Spark作业

导航到示例目录并提交Spark作业。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-eks-ipv6/examples/karpenter
kubectl apply -f pyspark-pi-job.yaml
```

使用以下命令监控作业状态。您应该看到由Karpenter触发的新节点。

```bash
kubectl get pods -n spark-team-a -w
```

### 使用基于NVMe的SSD磁盘进行shuffle存储的Apache YuniKorn组调度

使用Apache YuniKorn和Spark Operator进行组调度Spark作业

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-eks-ipv6/examples/karpenter/nvme-yunikorn-gang-scheduling
```

使用以下输入运行`taxi-trip-execute.sh`脚本。您将使用之前创建的`S3_BUCKET`变量。此外，您必须将YOUR_REGION_HERE更改为您选择的区域，例如us-west-2。

此脚本将下载一些示例出租车行程数据并创建其副本，以便稍微增加大小。这将花费一些时间，并且需要相对较快的互联网连接。

```bash
${DOEKS_HOME}/analytics/scripts/taxi-trip-execute.sh ${S3_BUCKET} YOUR_REGION_HERE
```

一旦我们的示例数据上传完成，您就可以运行Spark作业。您需要将此文件中的`<S3_BUCKET>`占位符替换为之前创建的存储桶名称。您可以通过运行echo $S3_BUCKET获取该值。

要自动执行此操作，您可以运行以下命令，它将创建一个.old备份文件并为您进行替换。

```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./nvme-storage-yunikorn-gang-scheduling.yaml
```

现在存储桶名称已就位，您可以创建Spark作业。

```bash
kubectl apply -f nvme-storage-yunikorn-gang-scheduling.yaml
```

## 清理

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-eks-ipv6 && chmod +x cleanup.sh
./cleanup.sh
```

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源
:::
