---
sidebar_position: 5
sidebar_label: Apache NiFi on EKS
---

# Apache NiFi on EKS

## 介绍

Apache NiFi 是一个开源数据集成和管理系统，旨在自动化和管理系统之间的数据流。它提供基于 Web 的用户界面，用于实时创建、监控和管理数据流。

凭借其强大而灵活的架构，Apache NiFi 可以处理广泛的数据源、云平台和格式，包括结构化和非结构化数据，并可用于各种数据集成场景，如数据摄取、数据处理（低到中等级别）、数据路由、数据转换和数据分发。

Apache NiFi 提供基于 GUI 的界面来构建和管理数据流，使非技术用户更容易使用。它还提供强大的安全功能，包括 SSL、SSH 和细粒度访问控制，以确保敏感数据的安全传输。无论您是数据分析师、数据工程师还是数据科学家，Apache NiFi 都为在 AWS 和其他平台上管理和集成数据提供了全面的解决方案。

:::caution

此蓝图应被视为实验性的，仅应用于概念验证。
:::

这个[示例](https://github.com/awslabs/data-on-eks/tree/main/streaming-platforms/nifi)部署了运行 Apache NiFi 集群的 EKS 集群。在示例中，Apache NiFi 在进行一些格式转换后将数据从 AWS Kinesis Data Stream 流式传输到 Amazon DynamoDB 表。

- 创建新的示例 VPC、3 个私有子网和 3 个公有子网
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关
- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的），包含一个托管节点组
- 部署 Apache NiFi、AWS Load Balancer Controller、Cert Manager 和 External DNS（可选）插件
- 在 `nifi` 命名空间中部署 Apache NiFi 集群

## 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [jq](https://stedolan.github.io/jq/)

此外，对于 Ingress 的端到端配置，您需要提供以下内容：

1. 在部署此示例的账户中配置的 [Route53 公共托管区域](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring.html)。例如 "example.com"
2. 在部署此示例的账户 + 区域中的 [ACM 证书](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html)。首选通配符证书，例如 "*.example.com"

## 部署带有 Apache NiFi 的 EKS 集群

### 克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

### 初始化 Terraform

导航到示例目录并运行 `terraform init`

```bash
cd data-on-eks/streaming/nifi/
terraform init
```

### Terraform 计划

运行 Terraform plan 以验证此执行创建的资源。

提供 Route53 托管区域主机名和相应的 ACM 证书；

```bash
export TF_VAR_eks_cluster_domain="<CHANGEME - example.com>"
export TF_VAR_acm_certificate_domain="<CHANGEME - *.example.com>"
export TF_VAR_nifi_sub_domain="nifi"
export TF_VAR_nifi_username="admin"
```

### 部署模式

```bash
terraform plan
terraform apply
```

输入 `yes` 以应用。

```
Outputs:

configure_kubectl = "aws eks --region us-west-2 update-kubeconfig --name nifi-on-eks"
```

### 验证部署

更新 kubeconfig

```bash
aws eks --region us-west-2 update-kubeconfig --name nifi-on-eks
```

验证所有 Pod 都在运行。

```bash
NAMESPACE           NAME                                                         READY   STATUS    RESTARTS      AGE
amazon-cloudwatch   aws-cloudwatch-metrics-7fbcq                                 1/1     Running   1 (43h ago)   2d
amazon-cloudwatch   aws-cloudwatch-metrics-82c9v                                 1/1     Running   1 (43h ago)   2d
amazon-cloudwatch   aws-cloudwatch-metrics-blrmt                                 1/1     Running   1 (43h ago)   2d
amazon-cloudwatch   aws-cloudwatch-metrics-dhpl7                                 1/1     Running   0             19h
amazon-cloudwatch   aws-cloudwatch-metrics-hpw5k                                 1/1     Running   1 (43h ago)   2d
cert-manager        cert-manager-7d57b6576b-c52dw                                1/1     Running   1 (43h ago)   2d
cert-manager        cert-manager-cainjector-86f7f4749-hs7d9                      1/1     Running   1 (43h ago)   2d
cert-manager        cert-manager-webhook-66c85f8577-rxms8                        1/1     Running   1 (43h ago)   2d
external-dns        external-dns-57bb948d75-g8kbs                                1/1     Running   0             41h
grafana             grafana-7f5b7f5d4c-znrqk                                     1/1     Running   1 (43h ago)   2d
kube-system         aws-load-balancer-controller-7ff998fc9b-86gql                1/1     Running   1 (43h ago)   2d
kube-system         aws-load-balancer-controller-7ff998fc9b-hct9k                1/1     Running   1 (43h ago)   2d
kube-system         aws-node-4gcqk                                               1/1     Running   1 (43h ago)   2d
kube-system         aws-node-4sssk                                               1/1     Running   0             19h
kube-system         aws-node-4t62f                                               1/1     Running   1 (43h ago)   2d
kube-system         aws-node-g4ndt                                               1/1     Running   1 (43h ago)   2d
kube-system         aws-node-hlxmq                                               1/1     Running   1 (43h ago)   2d
kube-system         cluster-autoscaler-aws-cluster-autoscaler-7bd6f7b94b-j7td5   1/1     Running   1 (43h ago)   2d
kube-system         cluster-proportional-autoscaler-coredns-6ccfb4d9b5-27xsd     1/1     Running   1 (43h ago)   2d
kube-system         coredns-5c5677bc78-rhzkx                                     1/1     Running   1 (43h ago)   2d
kube-system         coredns-5c5677bc78-t7m5z                                     1/1     Running   1 (43h ago)   2d
kube-system         ebs-csi-controller-87c4ff9d4-ffmwh                           6/6     Running   6 (43h ago)   2d
kube-system         ebs-csi-controller-87c4ff9d4-nfw28                           6/6     Running   6 (43h ago)   2d
kube-system         ebs-csi-node-4mkc8                                           3/3     Running   0             19h
kube-system         ebs-csi-node-74xqs                                           3/3     Running   3 (43h ago)   2d
kube-system         ebs-csi-node-8cw8t                                           3/3     Running   3 (43h ago)   2d
kube-system         ebs-csi-node-cs9wp                                           3/3     Running   3 (43h ago)   2d
kube-system         ebs-csi-node-ktdb7                                           3/3     Running   3 (43h ago)   2d
kube-system         kube-proxy-4s72m                                             1/1     Running   0             19h
kube-system         kube-proxy-95ptn                                             1/1     Running   1 (43h ago)   2d
kube-system         kube-proxy-bhrdk                                             1/1     Running   1 (43h ago)   2d
kube-system         kube-proxy-nzvb6                                             1/1     Running   1 (43h ago)   2d
kube-system         kube-proxy-q9xkc                                             1/1     Running   1 (43h ago)   2d
kube-system         metrics-server-fc87d766-dd647                                1/1     Running   1 (43h ago)   2d
kube-system         metrics-server-fc87d766-vv8z9                                1/1     Running   1 (43h ago)   2d
logging             aws-for-fluent-bit-b5vqg                                     1/1     Running   1 (43h ago)   2d
logging             aws-for-fluent-bit-pklhr                                     1/1     Running   0             19h
logging             aws-for-fluent-bit-rq2nc                                     1/1     Running   1 (43h ago)   2d
logging             aws-for-fluent-bit-tnmtl                                     1/1     Running   1 (43h ago)   2d
logging             aws-for-fluent-bit-zzhfc                                     1/1     Running   1 (43h ago)   2d
nifi                nifi-0                                                       5/5     Running   0             41h
nifi                nifi-1                                                       5/5     Running   0             41h
nifi                nifi-2                                                       5/5     Running   0             41h
nifi                nifi-registry-0                                              1/1     Running   0             41h
nifi                nifi-zookeeper-0                                             1/1     Running   0             41h
nifi                nifi-zookeeper-1                                             1/1     Running   0             41h
nifi                nifi-zookeeper-2                                             1/1     Running   0             18h
prometheus          prometheus-alertmanager-655fcb46df-2qh8h                     2/2     Running   2 (43h ago)   2d
prometheus          prometheus-kube-state-metrics-549f6d74dd-wwhtr               1/1     Running   1 (43h ago)   2d
prometheus          prometheus-node-exporter-5cpzk                               1/1     Running   0             19h
prometheus          prometheus-node-exporter-8jhbk                               1/1     Running   1 (43h ago)   2d
prometheus          prometheus-node-exporter-nbd42                               1/1     Running   1 (43h ago)   2d
prometheus          prometheus-node-exporter-str6t                               1/1     Running   1 (43h ago)   2d
prometheus          prometheus-node-exporter-zkf5s                               1/1     Running   1 (43h ago)   2d
prometheus          prometheus-pushgateway-677c6fdd5-9tqkl                       1/1     Running   1 (43h ago)   2d
prometheus          prometheus-server-7bf9cbb9cf-b2zgl                           2/2     Running   2 (43h ago)   2d
vpa                 vpa-recommender-7c6bbb4f9b-rjhr7                             1/1     Running   1 (43h ago)   2d
vpa                 vpa-updater-7975b9dc55-g6zf6                                 1/1     Running   1 (43h ago)   2d
```

#### Apache NiFi UI

Apache NiFi 仪表板可以在以下 URL 打开："https://nifi.example.com/nifi"

![Apache NiFi Login](../../../../../../docs/blueprints/streaming-platforms/img/nifi.png)

运行以下命令检索 NiFi 用户的密码，默认用户名为 `admin`
```
aws secretsmanager get-secret-value --secret-id <nifi_login_password_secret_name from terraform outputs> --region <region> | jq '.SecretString' --raw-output
```
![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-canvas.png)

### 监控
Apache NiFi 可以使用 PrometheusReportingTask 报告的指标进行监控。JVM 指标默认禁用，让我们通过点击右上角的汉堡图标（三条水平线）导航到控制器设置来启用 JVM 指标。

![Apache NiFi Controller Settings](../../../../../../docs/blueprints/streaming-platforms/img/nifi-controller-settings.png)

接下来点击 `REPORTING TASK` 选项卡，然后点击 `+` 图标，在过滤器中搜索 `PrometheusReportingTask`。选择 `PrometheusReportingTask` 并点击 `ADD` 按钮。

![Apache NiFi Prometheus Reporting](../../../../../../docs/blueprints/streaming-platforms/img/nifi-prometheus-reporting.png)

prometheus 报告任务默认停止。

![Apache NiFi Reporting Task Edit](../../../../../../docs/blueprints/streaming-platforms/img/nifi-reporting-task-edit.png)

点击铅笔图标编辑任务并点击 PROPERTIES 选项卡。将 `Send JVM metrics` 设置为 `true` 并点击 Apply。通过点击播放图标启动任务并确保它处于运行状态。

![Apache NiFi Reporting Task True](../../../../../../docs/blueprints/streaming-platforms/img/nifi-reporting-task-true.png)

此蓝图使用 `prometheus` 和 `grafana` 创建监控堆栈，以获得对 Apache NiFi 集群的可见性。

```
aws secretsmanager get-secret-value --secret-id <grafana_secret_name from terraform outputs> --region <region> | jq '.SecretString' --raw-output
```

运行以下命令并使用 URL "http://localhost:8080" 打开 Grafana 仪表板。

```
kubectl port-forward svc/grafana -n grafana 8080:80
```

导入 Apache NiFi [Grafana 仪表板](https://grafana.com/grafana/dashboards/12314-nifi-prometheusreportingtask-dashboard/)

![Apache NiFi Grafana Dashboard](../../../../../../docs/blueprints/streaming-platforms/img/nifi-grafana.png)

### 示例

#### 创建用于访问 Amazon DynamoDB 和 AWS Kinesis 的 IAM 策略

1. 创建 AWS IAM 角色：创建具有访问 AWS Kinesis 数据流权限的 AWS IAM 角色，并将此角色分配给托管 Apache NiFi 的 AWS EKS 集群。

2. 附加 IAM 策略：将策略附加到 IAM 角色，该策略将对 Kinesis 数据流的访问限制为只读，并启用 EKS 角色写入 Amazon DynamoDB 表的 IAM 策略。以下是示例策略：

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Nifi-access-to-Kinesis",
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetRecords",
                "kinesis:GetShardIterator",
                "kinesis:ListStreams"
            ],
            "Resource": "arn:aws:kinesis:<REGION>:<ACCOUNT-ID>:stream/kds-stream-nifi-on-EKS"
        }
    ]
}
```

```
{
    "Sid": "DynamoDBTableAccess",
    "Effect": "Allow",
    "Action": [
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:ConditionCheckItem",
        "dynamodb:PutItem",
        "dynamodb:DescribeTable",
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:Query",
        "dynamodb:UpdateItem"
    ],
    "Resource": "arn:aws:dynamodb:<REGION>:<ACCOUNT-ID>:table/NifiStreamingTable"
}
```

#### 创建 AWS Kinesis Data Stream
3. 创建 AWS Kinesis 数据流：登录 AWS 管理控制台，在您要收集数据的区域创建 Kinesis 数据流，或使用以下命令行创建一个。

```
aws kinesis create-stream --stream-name kds-stream-nifi-on-EKS
```

#### 创建 Amazon DynamoDB 表
4. 使用 AWS 控制台或命令行在同一 AWS 账户中创建 Amazon DynamoDB。创建一个包含 Amazon DynamoDB 表信息的 JSON 文件，名为 JSONSchemaDynamoDBTABLE.json

```

    "TableName": "NifiStreamingTable",
    "KeySchema": [
      { "AttributeName": "Name", "KeyType": "HASH" },
      { "AttributeName": "Age", "KeyType": "RANGE" }},
      { "AttributeName": "Location", "KeyType": "RANGE" }
    ],
    "AttributeDefinitions": [
      { "AttributeName": "Name", "KeyType": "S" },
      { "AttributeName": "Age", "KeyType": "S" }},
      { "AttributeName": "Location", "KeyType": "S" }
    ],
    "ProvisionedThroughput": {
      "ReadCapacityUnits": 5,
      "WriteCapacityUnits": 5
    }
}
```

5. 执行命令行从 JSON 文件创建 Amazon DynamoDB 表。

```
aws dynamodb create-table --cli-input-json  JSONSchemaDynamoDBTABLE.json
```

6. 使用端点打开 EKS 上的 Apache NiFi UI，创建一个进程组，并将其命名为 NifiStreamingExample。

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-1.png)

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-2.png)

7. 双击 Nifi-on-EKS-process-group 并进入进程以创建数据流。从左上角拖动处理器图标，在搜索窗口中输入 Kinesis，然后选择 ConsumeKinesisStream 处理器。要创建 Kinesis 消费者，请点击 ADD。

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-3.png)

8. 双击 Kinesis 处理器，选择属性选项卡，并填写以下配置信息。
   a. Amazon Kinesis Stream Name
   b. Application Name
   c. Region
   d. AWS Credentials Provider Service - 选择 AWSCredentialsProviderControllerService 并创建一个。

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-4.png)

#### 创建 AWS 凭证设置

9. 使用 AWS Credentials Provider Service 设置 AWS 凭证以访问账户中的 AWS 资源。在此示例中，我们使用访问密钥和秘密密钥。<em>**注意**：其他选项是基于 IAM 角色的、假设角色选项来验证 AWS 资源。</em>

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-5.png)

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-6.png)

10. 从左上角拖动处理器图标，在搜索窗口中输入"dynamoDB"，然后选择"PutDynamoDBRecord 处理器。点击 ADD 创建 Amazon DynamoDB 写入器。使用以下字段配置处理器。

a. Record Reader - 将其更改为 JSONTreeReader
b. AWS Credentials Provider Service - 选择之前创建的配置
c. Region
b. Table Name
d. Partition Key Field - 选择分区字段

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-7.png)
![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-8.png)
![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-9.png)

11. 悬停在 Kinesis 消费者上并将其拖动到 DynamoDB 写入器。将建立连接，并创建成功队列。

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-10.png)

12. 对于 Kinesis 消费者和 DynamoDB，创建到漏斗的错误路由。这是为了路由未处理、失败和成功的记录以进行进一步处理。注意：在关系选项卡下，您可以看到每个处理器的所有选项。对于 DynamoDB 写入器，成功应始终指向漏斗。

![Apache NiFi Canvas](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-11.png)

13. 检查没有处理器有任何危险符号。右键单击网格并点击"运行数据流"。您可以开始看到数据流入。

## 清理

要清理您的环境，请按相反顺序销毁 Terraform 模块。

销毁 Kubernetes 插件、EKS 集群与节点组和 VPC

```bash
terraform destroy -target="module.eks_blueprints_kubernetes_addons" --auto-approve
terraform destroy -target="module.eks" --auto-approve
terraform destroy -target="module.vpc" --auto-approve
```

最后，销毁不在上述模块中的任何其他资源

```bash
terraform destroy --auto-approve
```
