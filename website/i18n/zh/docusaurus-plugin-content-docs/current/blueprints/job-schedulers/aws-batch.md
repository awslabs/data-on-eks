---
title: AWS Batch on EKS
sidebar_position: 5
---

# AWS Batch on EKS
AWS Batch是一个完全托管的AWS原生批处理计算服务，它在Amazon Elastic Kubernetes Service (EKS)等AWS托管容器编排服务之上规划、调度和运行您的容器化批处理工作负载（机器学习、模拟和分析）。

AWS Batch为高性能计算工作负载添加了必要的操作语义和资源，使其能够在您现有的EKS集群上高效且经济地运行。

具体来说，Batch提供了一个始终在线的作业队列来接受工作请求。您创建一个AWS Batch作业定义，这是作业的模板，然后将其提交到Batch作业队列。然后，Batch负责为您的EKS集群在Batch特定的命名空间中配置节点，并在这些实例上放置pod来运行您的工作负载。

此示例提供了一个蓝图，用于建立一个完整的环境，使用AWS Batch在Amazon EKS集群上运行您的工作负载，包括：
* 所有必要的支持基础设施，如VPC、IAM角色、安全组等。
* 用于您工作负载的EKS集群
* 用于在EC2按需实例和竞价实例上运行作业的AWS Batch资源。

您可以在[这里](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/aws-batch-eks)找到蓝图。

## 考虑因素

AWS Batch适用于离线分析和数据处理任务，如媒体重新格式化、训练ML模型、批量推理或其他与用户不交互的计算和数据密集型任务。

特别是，Batch*针对运行时间超过三分钟的作业进行了优化*。如果您的作业很短（少于一分钟），请考虑在单个AWS Batch作业请求中打包更多工作，以增加作业的总运行时间。

## 先决条件

确保您在本地安装了以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 部署

**要配置此示例：**

1. 将仓库克隆到您的本地机器。
   ```bash
   git clone https://github.com/awslabs/data-on-eks.git
   cd data-on-eks/schedulers/terraform/aws-batch
   ```
2. 运行安装脚本。
   ```bash
   /bin/sh install.sh
   ```
   在命令提示符处输入区域以继续。

脚本将运行Terraform来建立所有资源。完成后，您将看到如下的terraform输出。

![terraform输出](../../../../../../docs/blueprints/job-schedulers/img/aws-batch/tf-apply-output.png)

以下组件将在您的环境中配置：

- 一个示例VPC，有2个私有子网和2个公共子网
- 公共子网的互联网网关和私有子网的NAT网关
- 带有一个托管节点组的EKS集群控制平面。
- EKS托管附加组件：VPC_CNI、CoreDNS、EBS_CSI_Driver、CloudWatch
- AWS Batch资源，包括
  - 一个按需计算环境和作业队列
  - 一个竞价计算环境和作业队列
  - 一个示例Batch作业定义，运行`echo "hello world!"`

## 验证

## 使用AWS Batch在EKS集群上运行示例作业

以下命令将更新您本地机器上的`kubeconfig`，并允许您使用`kubectl`与EKS集群交互以验证部署。

### 运行`update-kubeconfig`命令

从`terraform apply`的`configure_kubectl_cmd`输出值运行命令。如果您没有这个，可以使用`terraform output`命令获取terraform堆栈输出值。

```bash
# 不要复制这个！这只是一个示例，请参阅上面的内容了解要运行什么。
aws eks --region us-east-1 update-kubeconfig --name doeks-batch
```

### 列出节点

一旦配置了`kubectl`，您可以使用它来检查集群节点和命名空间。要获取节点信息，请运行以下命令。

```bash
kubectl get nodes
```

输出应该如下所示。

```
NAME                           STATUS   ROLES    AGE    VERSION
ip-10-1-107-168.ec2.internal   Ready    <none>   3m7s   v1.30.2-eks-1552ad0
ip-10-1-141-25.ec2.internal    Ready    <none>   3m7s   v1.30.2-eks-1552ad0
```

要获取集群的创建命名空间，请运行以下命令。

```bash
kubectl get ns
```

输出应该如下所示。

```
NAME                STATUS   AGE
amazon-cloudwatch   Active   2m22s
default             Active   10m
doeks-aws-batch     Active   103s
kube-node-lease     Active   10m
kube-public         Active   10m
kube-system         Active   10m
```

命名空间`doeks-aws-batch`将被Batch用来添加Batch管理的EC2实例作为节点，并在这些节点上运行作业。

:::note
AWS Batch kubernetes命名空间可以作为terraform的输入变量进行配置。如果您选择在`variables.tf`文件中更改它，那么您需要调整后续命令以适应更改。
:::

### 运行"Hello World!"作业

`terraform apply`的输出包含了在按需和竞价作业队列上运行示例**Hello World!**作业定义的AWS CLI命令。您可以使用`terraform output`再次查看这些命令。

**要在按需资源上运行示例作业定义：**

1. 运行terraform输出`run_example_aws_batch_job`提供的命令。它应该看起来像：
   ```bash
   JOB_ID=$(aws batch --region us-east-1  submit-job --job-definition arn:aws:batch:us-east-1:653295002771:job-definition/doeks-hello-world:2 --job-queue doeks-JQ1_OD --job-name doeks_hello_example --output text --query jobId) && echo $JOB_ID
   ## 输出应该是Batch作业ID
   be1f781d-753e-4d10-a7d4-1b6de68574fc
   ```
   响应将填充`JOB_ID`shell变量，您可以在后续步骤中使用它。

## 检查状态

您可以使用AWS CLI从AWS Batch API检查作业的状态：

```bash
aws batch --no-cli-pager \
describe-jobs --jobs $JOB_ID --query "jobs[].[jobId,status]"
```

这将输出类似以下内容：

```
[
    [
        "a13e1cff-121c-4a0b-a9c5-fab953136e20",
        "RUNNABLE"
    ]
]
```

:::tip
如果您看到空结果，可能是因为您使用的默认AWS区域与部署到的区域不同。通过设置`AWS_DEFAULT_REGION` shell变量来调整默认区域的值。

```bash
export AWS_DEFAULT_REGION=us-east-1
```
:::

我们可以使用`kubectl`监控Batch管理的节点和Pod的状态。首先，让我们跟踪节点的启动和加入集群：

```bash
kubectl get nodes -w
```
这将持续监控EKS节点的状态，并定期输出它们的就绪状态。

```
NAME                           STATUS   ROLES    AGE   VERSION
ip-10-1-107-168.ec2.internal   Ready    <none>   12m   v1.30.2-eks-1552ad0
ip-10-1-141-25.ec2.internal    Ready    <none>   12m   v1.30.2-eks-1552ad0
ip-10-1-60-65.ec2.internal     NotReady   <none>   0s    v1.30.2-eks-1552ad0
ip-10-1-60-65.ec2.internal     NotReady   <none>   0s    v1.30.2-eks-1552ad0
ip-10-1-60-65.ec2.internal     NotReady   <none>   0s    v1.30.2-eks-1552ad0
# ... 更多行
```

当新的Batch管理的节点正在启动（状态为**NotReady**的新节点）时，您可以按`Control-c`键组合退出监视进程。这将允许您监控在AWS Batch命名空间中启动的pod的状态：

```bash
kubectl get pods -n doeks-aws-batch -w
```
:::note
AWS Batch kubernetes命名空间可以作为terraform的输入变量进行配置。如果您选择在`variables.tf`文件中更改它，那么您需要调整前面的命令以适应更改。
:::

这将持续监控Batch放置在集群上的Pod的状态，并定期输出它们的状态。

```
NAME                                             READY   STATUS    RESTARTS   AGE
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Pending   0          0s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     ContainerCreating   0          0s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   1/1     Running             0          17s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Completed           0          52s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Completed           0          53s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Terminating         0          53s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Terminating         0          53s
```

一旦Pod处于**Terminating**状态，您可以通过按`Control-c`键组合退出监视进程。要从AWS Batch查看作业的状态，请使用以下命令：

```bash
aws batch --no-cli-pager \
describe-jobs --jobs $JOB_ID --query "jobs[].[jobId,status]"
```

这将显示作业ID和状态，应该是`SUCCEEDED`。

```
[
    [
        "a13e1cff-121c-4a0b-a9c5-fab953136e20",
        "SUCCEEDED"
    ]
]
```

要在CloudWatch日志组管理控制台中找到应用程序容器日志，我们需要应用程序容器的Pod名称。`kubestl get pods`输出没有给我们一个好方法来确定哪些Pod是具有应用程序容器的Pod。此外，一旦Pod终止，Kubernetes调度器就无法再提供有关作业的节点或Pod的任何信息。好在AWS Batch保留了作业的记录！

我们可以使用AWS Batch的API查询主节点的`podName`和其他信息。要获取MNP作业中特定节点的信息，您可以在作业ID后面加上模式`"#<NODE_INDEX>"`。对于我们在作业定义中定义为索引`"0"`的主节点，这将转换为以下AWS CLI命令：

```bash
aws batch describe-jobs --jobs "$JOB_ID" --query "jobs[].eksAttempts[].{nodeName: nodeName, podName: podName}"
```

输出应该类似于以下内容。

```
[
    {
        "nodeName": "ip-10-1-60-65.ec2.internal",
        "podName": "aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1"
    }
]
```

**要查看应用程序容器日志：**
1. 导航到[Amazon CloudWatch管理控制台日志组面板](https://console.aws.amazon.com/cloudwatch/home?#logsV2:log-groups$3FlogGroupNameFilter$3Ddoeks-batch)。
2. 在**日志组**列表表中，选择集群的应用程序日志。这些由集群的名称和后缀`application`标识。
   ![CloudWatch管理控制台，显示应用程序日志的位置。](../../../../../../docs/blueprints/job-schedulers/img/aws-batch/cw-logs-1.png)
3. 在**日志流**列表表中，输入上一步中`podName`的值。这将突出显示Pod中两个容器的两个日志。选择`application`容器的日志流。
   ![CloudWatch日志流面板显示使用pod名称过滤的集合。](../../../../../../docs/blueprints/job-schedulers/img/aws-batch/cw-logs-2.png)
4. 在**日志事件**部分，在过滤栏中，选择**显示**，然后选择**以纯文本查看"。您应该在日志事件的`"log"`属性中看到"Hello World!"日志消息。

## 清理

要清理您的环境&mdash;从集群中删除所有AWS Batch资源和kubernetes构造&mdash;运行`cleanup.sh`脚本。

```bash
chmod +x cleanup.sh
./cleanup.sh
```

为了避免来自CloudWatch日志的数据费用，您还应该从集群中删除日志组。您可以通过导航到[CloudWatch管理控制台的**日志组**页面](https://console.aws.amazon.com/cloudwatch/home?#logsV2:log-groups$3FlogGroupNameFilter$3Ddoeks-batch)找到这些。
