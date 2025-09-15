---
title: Amazon MWAA
sidebar_position: 2
---

# Amazon Managed Workflows for Apache Airflow (MWAA)
Amazon Managed Workflows for Apache Airflow (MWAA) 是 Apache Airflow 的托管编排服务，使在云中大规模设置和操作端到端数据管道变得更加容易。Apache Airflow 是一个开源工具，用于以编程方式创作、调度和监控称为"工作流"的进程和任务序列。使用托管工作流，您可以使用 Airflow 和 Python 创建工作流，而无需管理可扩展性、可用性和安全性的底层基础设施。

该示例演示了如何使用 [Amazon Managed Workflows for Apache Airflow (MWAA)](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html) 以两种方式将作业分配给 Amazon EKS。
1. 直接创建作业并部署到 EKS。
2. 在 EMR 中将 EKS 注册为虚拟集群，并将 spark 作业分配给 EMR on EKS。

此示例的[代码存储库](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/managed-airflow-mwaa)。

### 注意事项

理想情况下，我们建议将同步 requirements/sync dags 到 MWAA S3 存储桶的步骤添加为 CI/CD 管道的一部分。通常，Dags 开发与配置基础设施的 Terraform 代码具有不同的生命周期。
为简单起见，我们使用在 `null_resource` 上运行 AWS CLI 命令的 Terraform 提供了相关步骤。

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

完成后，您将看到如下的 terraform 输出。

![terraform output](../../../../../../docs/blueprints/job-schedulers/img/terraform-output.png)

在您的环境中配置了以下组件：
  - 示例 VPC、3 个私有子网和 3 个公有子网
  - 公有子网的互联网网关和私有子网的 NAT 网关
  - 带有一个托管节点组的 EKS 集群控制平面
  - EKS 托管插件：VPC_CNI、CoreDNS、Kube_Proxy、EBS_CSI_Driver
  - K8S metrics server 和 cluster autoscaler
  - 版本 2.2.2 的 MWAA 环境
  - 在新创建的 EKS 中注册的 EMR 虚拟集群
  - 包含 DAG 代码的 S3 存储桶

## 验证

以下命令将更新本地机器上的 `kubeconfig`，并允许您使用 `kubectl` 与 EKS 集群交互以验证部署。

### 运行 `update-kubeconfig` 命令

运行以下命令。您也可以从 terraform 输出 'configure_kubectl' 复制命令。
```bash
aws eks --region us-west-2 update-kubeconfig --name managed-airflow-mwaa
```

### 列出节点

```bash
kubectl get nodes

# 输出应如下所示
NAME                         STATUS   ROLES    AGE     VERSION
ip-10-0-0-42.ec2.internal    Ready    <none>   5h15m   v1.26.4-eks-0a21954
ip-10-0-22-71.ec2.internal   Ready    <none>   5h15m   v1.26.4-eks-0a21954
ip-10-0-44-63.ec2.internal   Ready    <none>   5h15m   v1.26.4-eks-0a21954
```

### 列出 EKS 集群中的命名空间

```bash
kubectl get ns

# 输出应如下所示
default           Active   4h38m
emr-mwaa          Active   4h34m
kube-node-lease   Active   4h39m
kube-public       Active   4h39m
kube-system       Active   4h39m
mwaa              Active   4h30m
```

命名空间 `emr-mwaa` 将被 EMR 用于运行 spark 作业。<br />
命名空间 `mwaa` 将被 MWAA 直接使用。

## 从 MWAA 触发作业

### 登录 Apache Airflow UI

- 在 Amazon MWAA 控制台上打开环境页面
- 选择一个环境
- 在 `Details` 部分下，点击 Airflow UI 的链接<br />

注意：登录后您会看到红色错误消息。这是因为尚未设置 EMR 连接。按照以下步骤设置连接并重新登录后，消息将消失。

### 触发 DAG 工作流以在 EMR on EKS 中执行作业

首先，您需要在 MWAA 中设置到 EMR 虚拟集群的连接

![add connection](../../../../../../docs/blueprints/job-schedulers/img/add-connection.png)

- 点击 Add 按钮，<br />
- 确保使用 `emr_eks` 作为连接 ID <br />
- `Amazon Web Services` 作为连接类型 <br />
- 根据您的 terraform 输出替换 `Extra` 中的值 <br />
`{"virtual_cluster_id":"<emrcontainers_virtual_cluster_id in terraform output>", "job_role_arn":"<emr_on_eks_role_arn in terraform output>"}`

![Add a new connection](../../../../../../docs/blueprints/job-schedulers/img/emr-eks-connection.png)

返回 Airflow UI 主页，启用示例 DAG `emr_eks_pi_job`，然后触发作业。

![trigger EMR](../../../../../../docs/blueprints/job-schedulers/img/trigger-emr.png)

运行时，使用以下命令验证 spark 作业：

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

您还可以在 Amazon EMR 控制台中检查作业状态。在 `Virtual clusters` 部分下，点击虚拟集群

![EMR job status](../../../../../../docs/blueprints/job-schedulers/img/emr-job-status.png)

### 触发 DAG 工作流以在 EKS 中执行作业

在 Airflow UI 中，启用示例 DAG kubernetes_pod_example，然后触发它。

![Enable the DAG kubernetes_pod_example](../../../../../../docs/blueprints/job-schedulers/img/kubernetes-pod-example-dag.png)

![Trigger the DAG kubernetes_pod_example](../../../../../../docs/blueprints/job-schedulers/img/dag-tree.png)

验证 Pod 是否成功执行

运行并成功完成后，使用以下命令验证 Pod：

```bash
kubectl get pods -n mwaa
```

您应该看到类似以下的输出：

```bash
NAME                                             READY   STATUS      RESTARTS   AGE
mwaa-pod-test.4bed823d645844bc8e6899fd858f119d   0/1     Completed   0          25s
```

## 销毁

要清理您的环境，请运行 `cleanup.sh` 脚本。

```bash
chmod +x cleanup.sh
./cleanup.sh
```
---
