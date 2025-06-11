---
title: Amazon MWAA
sidebar_position: 2
---

# Amazon Managed Workflows for Apache Airflow (MWAA)
Amazon Managed Workflows for Apache Airflow (MWAA)是一个托管的Apache Airflow编排服务，它使在云中大规模设置和运行端到端数据管道变得更加容易。Apache Airflow是一个开源工具，用于以编程方式创作、调度和监控被称为"工作流"的过程和任务序列。使用Managed Workflows，您可以使用Airflow和Python创建工作流，而无需管理可扩展性、可用性和安全性的底层基础设施。

该示例演示了如何通过两种方式使用[Amazon Managed Workflows for Apache Airflow (MWAA)](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html)将作业分配给Amazon EKS。
1. 直接创建作业并部署到EKS。
2. 将EKS注册为EMR中的虚拟集群，并将spark作业分配给EMR on EKS。

此示例的[代码仓库](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/managed-airflow-mwaa)。

### 注意事项

理想情况下，我们建议将同步requirements/同步dags到MWAA S3存储桶的步骤作为CI/CD管道的一部分。通常，Dags开发的生命周期与配置基础设施的Terraform代码不同。
为简单起见，我们提供了使用Terraform在`null_resource`上运行AWS CLI命令的步骤。

## 先决条件：

确保您已在本地安装了以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 部署

要配置此示例：

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/schedulers/terraform/managed-airflow-mwaa
chmod +x install.sh
./install.sh
```

在命令提示符处输入区域以继续。

完成后，您将看到如下terraform输出。

![terraform输出](../../../../../../docs/blueprints/job-schedulers/img/terraform-output.png)

在您的环境中配置了以下组件：
  - 一个示例VPC、3个私有子网和3个公共子网
  - 公共子网的互联网网关和私有子网的NAT网关
  - 带有一个托管节点组的EKS集群控制平面
  - EKS托管附加组件：VPC_CNI、CoreDNS、Kube_Proxy、EBS_CSI_Driver
  - K8S指标服务器和集群自动扩缩器
  - 版本为2.2.2的MWAA环境
  - 一个注册到新创建的EKS的EMR虚拟集群
  - 一个带有DAG代码的S3存储桶

## 验证

以下命令将更新您本地机器上的`kubeconfig`，并允许您使用`kubectl`与EKS集群交互以验证部署。

### 运行`update-kubeconfig`命令

运行下面的命令。您也可以从terraform输出'configure_kubectl'中复制命令。
```bash
aws eks --region us-west-2 update-kubeconfig --name managed-airflow-mwaa
```

### 列出节点

```bash
kubectl get nodes

# 输出应该如下所示
NAME                         STATUS   ROLES    AGE     VERSION
ip-10-0-0-42.ec2.internal    Ready    <none>   5h15m   v1.26.4-eks-0a21954
ip-10-0-22-71.ec2.internal   Ready    <none>   5h15m   v1.26.4-eks-0a21954
ip-10-0-44-63.ec2.internal   Ready    <none>   5h15m   v1.26.4-eks-0a21954
```

### 列出EKS集群中的命名空间

```bash
kubectl get ns

# 输出应该如下所示
default           Active   4h38m
emr-mwaa          Active   4h34m
kube-node-lease   Active   4h39m
kube-public       Active   4h39m
kube-system       Active   4h39m
mwaa              Active   4h30m
```

命名空间`emr-mwaa`将被EMR用于运行spark作业。<br />
命名空间`mwaa`将直接被MWAA使用。


## 从MWAA触发作业

### 登录Apache Airflow UI

- 在Amazon MWAA控制台上打开环境页面
- 选择一个环境
- 在`Details`部分下，点击Airflow UI的链接<br />

注意：登录后您将看到红色错误消息。这是因为EMR连接尚未设置。按照以下步骤设置连接并再次登录后，消息将消失。

### 触发DAG工作流以在EMR on EKS中执行作业

首先，您需要在MWAA中设置与EMR虚拟集群的连接

![添加连接](../../../../../../docs/blueprints/job-schedulers/img/add-connection.png)

- 点击添加按钮，<br />
- 确保使用`emr_eks`作为Connection Id <br />
- `Amazon Web Services`作为Connection Type <br />
- 根据您的terraform输出替换`Extra`中的值 <br />
`{"virtual_cluster_id":"<terraform输出中的emrcontainers_virtual_cluster_id>", "job_role_arn":"<terraform输出中的emr_on_eks_role_arn>"}`

![添加新连接](../../../../../../docs/blueprints/job-schedulers/img/emr-eks-connection.png)

返回Airflow UI主页，启用示例DAG `emr_eks_pi_job`，然后触发作业。

![触发EMR](../../../../../../docs/blueprints/job-schedulers/img/trigger-emr.png)

在运行时，使用以下命令验证spark作业：

```bash
kubectl get all -n emr-mwaa
```

您应该看到类似以下的输出：

```bash
NAME                                   READY   STATUS    RESTARTS   AGE
pod/000000030tk2ihdmr8g-psstj          3/3     Running   0          90s
pod/pythonpi-a8051f83b415c911-exec-1   2/2     Running   0          14s
pod/pythonpi-a8051f83b415c911-exec-2   2/2     Running   0          14s
pod/spark-000000030tk2ihdmr8g-driver   2/2     Running   0          56s

NAME                                                            TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                      AGE
service/spark-000000030tk2ihdmr8g-ee64be83b4151dd5-driver-svc   ClusterIP   None         <none>        7078/TCP,7079/TCP,4040/TCP   57s

NAME                            COMPLETIONS   DURATION   AGE
job.batch/000000030tk2ihdmr8g   0/1           92s        92s
```

您还可以在Amazon EMR控制台中检查作业状态。在`Virtual clusters`部分下，点击Virtual cluster

![EMR作业状态](../../../../../../docs/blueprints/job-schedulers/img/emr-job-status.png)

### 触发DAG工作流以在EKS中执行作业

在Airflow UI中，启用示例DAG kubernetes_pod_example，然后触发它。

![启用DAG kubernetes_pod_example](../../../../../../docs/blueprints/job-schedulers/img/kubernetes-pod-example-dag.png)

![触发DAG kubernetes_pod_example](../../../../../../docs/blueprints/job-schedulers/img/dag-tree.png)

验证pod是否成功执行

在它成功运行并完成后，使用以下命令验证pod：

```bash
kubectl get pods -n mwaa
```

您应该看到类似以下的输出：

```bash
NAME                                             READY   STATUS      RESTARTS   AGE
mwaa-pod-test.4bed823d645844bc8e6899fd858f119d   0/1     Completed   0          25s
```

## 销毁

要清理您的环境，运行`cleanup.sh`脚本。

```bash
chmod +x cleanup.sh
./cleanup.sh
```
---
