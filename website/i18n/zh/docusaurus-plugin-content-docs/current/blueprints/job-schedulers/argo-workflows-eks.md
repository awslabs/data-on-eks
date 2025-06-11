---
title: EKS上的Argo Workflows
sidebar_position: 4
---
# EKS上的Argo Workflows
Argo Workflows是一个开源的容器原生工作流引擎，用于在Kubernetes上编排并行作业。它作为Kubernetes CRD（自定义资源定义）实现。因此，Argo工作流可以使用kubectl进行管理，并与其他Kubernetes服务（如卷、密钥和RBAC）原生集成。

该示例演示了如何使用[Argo Workflows](https://argoproj.github.io/argo-workflows/)向Amazon EKS分配作业。

1. 使用Argo Workflows创建spark作业。
2. 通过spark操作符使用Argo Workflows创建spark作业。
3. 使用[Argo Events](https://argoproj.github.io/argo-events/)基于Amazon SQS消息插入事件触发Argo Workflows创建spark作业。

此示例的[代码仓库](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/argo-workflow)。

## 先决条件：

确保您在本地安装了以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [Argo WorkflowCLI](https://github.com/argoproj/argo-workflows/releases/latest)

## 部署

要配置此示例：

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/schedulers/terraform/argo-workflow

region=<your region> # 为以下命令设置区域变量
terraform init
terraform apply -var region=$region #默认为us-west-2
```

在命令提示符处输入`yes`以应用

以下组件将在您的环境中配置：
- 一个示例VPC，2个私有子网和2个公共子网
- 公共子网的互联网网关和私有子网的NAT网关
- 带有一个托管节点组的EKS集群控制平面
- EKS托管附加组件：VPC_CNI、CoreDNS、Kube_Proxy、EBS_CSI_Driver
- K8S指标服务器、CoreDNS自动扩展器、集群自动扩展器、AWS for FluentBit、Karpenter、Argo Workflows、Argo Events、Kube Prometheus Stack、Spark操作符和Yunikorn调度器
- Argo Workflows和Argo Events的K8s角色和角色绑定

![terraform-output](../../../../../../docs/blueprints/job-schedulers/img/terraform-output-argo.png)

## 验证

以下命令将更新您本地机器上的`kubeconfig`，并允许您使用`kubectl`与EKS集群交互以验证部署。

### 运行`update-kubeconfig`命令：

```bash
aws eks --region eu-west-1 update-kubeconfig --name argoworkflows-eks
```

### 列出节点

```bash
kubectl get nodes

# 输出应该类似于以下内容
NAME                                       STATUS   ROLES    AGE   VERSION
ip-10-1-0-189.eu-west-1.compute.internal   Ready    <none>   10m   v1.27.3-eks-a5565ad
ip-10-1-0-240.eu-west-1.compute.internal   Ready    <none>   10m   v1.27.3-eks-a5565ad
ip-10-1-1-135.eu-west-1.compute.internal   Ready    <none>   10m   v1.27.3-eks-a5565ad
```

### 列出EKS集群中的命名空间

```bash
kubectl get ns

# 输出应该类似于以下内容
NAME                    STATUS   AGE
argo-events             Active   7m45s
argo-workflows           Active   8m25s
spark-team-a            Active   5m51s
default                 Active   25m
karpenter               Active   21m
kube-node-lease         Active   25m
kube-prometheus-stack   Active   8m5s
kube-public             Active   25m
kube-system             Active   25m
spark-operator          Active   5m43s
yunikorn                Active   5m44s
```

### 访问Argo Workflow WebUI

获取负载均衡器URL：

```bash
kubectl -n argo-workflows get service argo-workflows-server -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}"
```

将结果复制并粘贴到您的浏览器中。
初始用户名是`admin`。登录令牌是自动生成的，您可以通过运行以下命令获取：

```bash
argo auth token # 获取登录令牌

# 结果：
Bearer k8s-aws-v1.aHR0cHM6Ly9zdHMudXMtd2VzdC0yLmFtYXpvbmF3cy5jb20vP0FjdGlvbj1HZXRDYWxsZXJJZGVudGl0eSZWZXJzaW9uPTIwMTEtMDYtMTUmWC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNWNFhDV1dLUjZGVTRGMiUyRjIwMjIxMDEzJTJGdXMtd2VzdC0yJTJGc3RzJTJGYXdzNF9yZXF1ZXN0JlgtQW16LURhdGU9MjAyMjEwMTNUMDIyODAyWiZYLUFtei1FeHBpcmVzPTYwJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCUzQngtazhzLWF3cy1pZCZYLUFtei1TaWduYXR1cmU9NmZiNmMxYmQ0MDQyMWIwNTI3NjY4MzZhMGJiNmUzNjg1MTk1YmM0NDQzMjIyMTg5ZDNmZmE1YzJjZmRiMjc4OA
```

![argo-workflow-login](../../../../../../docs/blueprints/job-schedulers/img/argo-workflow-login.png)

### 使用Argo Workflow提交Spark作业

从`terraform output`导出EKS API

```bash
eks_api_url=https://ABCDEFG1234567890.yl4.eu-west-2.eks.amazonaws.com

cat workflow-examples/argo-spark.yaml | sed "s/<your_eks_api_server_url>/$eks_api_url/g" | kubectl apply -f -

kubectl get wf -n argo-workflows
NAME    STATUS    AGE   MESSAGE
spark   Running   8s
```

您还可以从Web UI检查工作流状态

![argo-wf-spark](../../../../../../docs/blueprints/job-schedulers/img/argo-wf-spark.png)

### 使用Spark操作符和Argo Workflow提交Spark作业

```bash
kubectl apply -f workflow-examples/argo-spark-operator.yaml

kubectl get wf -n argo-workflows
NAME             STATUS      AGE     MESSAGE
spark            Succeeded   3m58s
spark-operator   Running     5s
```

Web UI中的工作流状态

![argo-wf-spark-operator](../../../../../../docs/blueprints/job-schedulers/img/argo-wf-spark-operator.png)

## 基于SQS消息触发工作流创建spark作业

### 安装[eventbus](https://argoproj.github.io/argo-events/eventbus/eventbus/)，用于argo events中的事件传输

```bash
kubectl apply -f argo-events-manifests/eventbus.yaml
```

### 部署`eventsource-sqs.yaml`以链接外部SQS

在这种情况下，我们配置一个EventSource来监听区域`us-east-1`中的队列`test1`。eventsource能够跨区域监控事件，因此Amazon EKS集群和Amazon SQS队列不需要位于同一区域。

```bash
queue_name=test1
region_sqs=us-east-1

cat argo-events-manifests/eventsource-sqs.yaml | sed "s/<region_sqs>/$region_sqs/g;s/<queue_name>/$queue_name/g" | kubectl apply -f -
```

让我们在您的账户中创建该队列。

```bash
# 创建队列
queue_url=$(aws sqs create-queue --queue-name $queue_name --region $region_sqs --output text)

# 获取您的队列arn
sqs_queue_arn=$(aws sqs get-queue-attributes --queue-url $queue_url --attribute-names QueueArn --region $region_sqs --query "Attributes.QueueArn" --output text)

template=`cat argo-events-manifests/sqs-accesspolicy.json | sed -e "s|<sqs_queue_arn>|$sqs_queue_arn|g;s|<your_event_irsa_arn>|$your_event_irsa_arn|g"`

aws sqs set-queue-attributes --queue-url $queue_url --attributes $template --region $region_sqs
```

### 部署`sensor-rbac.yaml`和`sensor-sqs-spark-crossns.yaml`用于触发工作流

```bash
kubectl apply -f argo-events-manifests/sensor-rbac.yaml
```

```bash
cd workflow-examples
```

更新Shell脚本中的变量并执行

```bash
./taxi-trip-execute.sh
```

更新YAML文件并运行以下命令

```bash
kubectl apply -f sensor-sqs-sparkjobs.yaml
```

### 验证argo-events命名空间

```bash
kubectl get all,eventbus,EventSource,sensor,sa,role,rolebinding -n argo-events

# 输出应该类似于以下内容
NAME                                                      READY   STATUS    RESTARTS   AGE
pod/argo-events-controller-manager-bfb894cdb-26qw7        1/1     Running   0          18m
pod/aws-sqs-crossns-spark-sensor-zkgz5-6584787c47-zjm9p   1/1     Running   0          44s
pod/aws-sqs-eventsource-544jd-8fccc6f8-w6ssd              1/1     Running   0          4m45s
pod/eventbus-default-stan-0                               2/2     Running   0          5m21s
pod/eventbus-default-stan-1                               2/2     Running   0          5m13s
pod/eventbus-default-stan-2                               2/2     Running   0          5m11s
pod/events-webhook-6f8d9fdc79-l9q9w                       1/1     Running   0          18m

NAME                                TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
service/eventbus-default-stan-svc   ClusterIP   None           <none>        4222/TCP,6222/TCP,8222/TCP   5m21s
service/events-webhook              ClusterIP   172.20.4.211   <none>        443/TCP                      18m

NAME                                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/argo-events-controller-manager       1/1     1            1           18m
deployment.apps/aws-sqs-crossns-spark-sensor-zkgz5   1/1     1            1           44s
deployment.apps/aws-sqs-eventsource-544jd            1/1     1            1           4m45s
deployment.apps/events-webhook                       1/1     1            1           18m

NAME                                                            DESIRED   CURRENT   READY   AGE
replicaset.apps/argo-events-controller-manager-bfb894cdb        1         1         1       18m
replicaset.apps/aws-sqs-crossns-spark-sensor-zkgz5-6584787c47   1         1         1       44s
replicaset.apps/aws-sqs-eventsource-544jd-8fccc6f8              1         1         1       4m45s
replicaset.apps/events-webhook-6f8d9fdc79                       1         1         1       18m

NAME                                     READY   AGE
statefulset.apps/eventbus-default-stan   3/3     5m21s

NAME                           AGE
eventbus.argoproj.io/default   5m22s

NAME                              AGE
eventsource.argoproj.io/aws-sqs   4m46s

NAME                                       AGE
sensor.argoproj.io/aws-sqs-crossns-spark   45s

NAME                                            SECRETS   AGE
serviceaccount/argo-events-controller-manager   0         18m
serviceaccount/argo-events-events-webhook       0         18m
serviceaccount/default                          0         18m
serviceaccount/event-sa                         0         16m
serviceaccount/operate-workflow-sa              0         53s

NAME                                                   CREATED AT
role.rbac.authorization.k8s.io/operate-workflow-role   2023-07-24T18:52:30Z

NAME                                                                  ROLE                         AGE
rolebinding.rbac.authorization.k8s.io/operate-workflow-role-binding   Role/operate-workflow-role   52s
```

### 从SQS测试

从SQS发送消息：`{"message": "hello"}`

```bash
aws sqs send-message --queue-url $queue_url --message-body '{"message": "hello"}' --region $region_sqs
```

Argo Events会捕获消息并触发Argo Workflows为spark作业创建工作流。

```bash
kubectl get wf -A

# 输出应该类似于以下内容
NAMESPACE        NAME                           STATUS    AGE   MESSAGE
argo-workflows   aws-sqs-spark-workflow-hh79p   Running   11s
```

运行以下命令检查spark-team-a命名空间下的spark应用程序驱动程序pod和执行器pod。

```bash
kubectl get po -n spark-team-a

# 输出应该类似于以下内容
NAME                               READY   STATUS    RESTARTS   AGE
event-wf-sparkapp-tcxl8-driver     1/1     Running   0          45s
pythonpi-a72f5f89894363d2-exec-1   1/1     Running   0          16s
pythonpi-a72f5f89894363d2-exec-2   1/1     Running   0          16s
```

在Web UI中查看SQS工作流状态

![argo-wf-spark-operator](../../../../../../docs/blueprints/job-schedulers/img/argo-wf-sqs-spark.png)

![argo-wf-spark-operator](../../../../../../docs/blueprints/job-schedulers/img/argo-wf-sqs-spark-tree.png)


## 销毁

要拆除并删除在此示例中创建的资源：

```bash
kubectl delete -f argo-events-manifests/.

./cleanup.sh
```
