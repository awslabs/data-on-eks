---
sidebar_position: 5
sidebar_label: Apache NiFi on EKS
---

# Apache NiFi on EKS

## 介绍

Apache NiFi是一个开源数据集成和管理系统，旨在自动化和管理系统之间的数据流。它提供了一个基于Web的用户界面，用于实时创建、监控和管理数据流。

凭借其强大而灵活的架构，Apache NiFi可以处理各种数据源、云平台和格式，包括结构化和非结构化数据，并可用于各种数据集成场景，如数据摄取、数据处理（低到中等级别）、数据路由、数据转换和数据传播。

Apache NiFi提供了一个基于GUI的界面来构建和管理数据流，使非技术用户更容易使用。它还提供了强大的安全功能，包括SSL、SSH和细粒度访问控制，以确保敏感数据的安全和安全传输。无论您是数据分析师、数据工程师还是数据科学家，Apache NiFi都为在AWS和其他平台上管理和集成数据提供了全面的解决方案。
:::caution

此蓝图应被视为实验性的，仅应用于概念验证。
:::

这个[示例](https://github.com/awslabs/data-on-eks/tree/main/streaming-platforms/nifi)部署了一个运行Apache NiFi集群的EKS集群。在示例中，Apache NIfi在进行一些格式转换后，将数据从AWS Kinesis Data Stream流式传输到Amazon DynamoDB表。

- 创建一个新的示例VPC、3个私有子网和3个公共子网
- 为公共子网创建互联网网关，为私有子网创建NAT网关
- 创建带有公共端点的EKS集群控制平面（仅用于演示原因）和一个托管节点组
- 部署Apache NiFi、AWS Load Balancer Controller、Cert Manager和External DNS（可选）附加组件
- 在`nifi`命名空间中部署Apache NiFi集群

## 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [jq](https://stedolan.github.io/jq/)

此外，对于端到端的Ingress配置，您需要提供以下内容：

1. 在您部署此示例的账户中配置的[Route53公共托管区域](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring.html)。例如"example.com"
2. 在您部署此示例的账户+区域中的[ACM证书](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html)。首选通配符证书，例如"*.example.com"

## 部署带有Apache NiFi的EKS集群

### 克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

### 初始化Terraform

导航到示例目录并运行`terraform init`

```bash
cd data-on-eks/streaming/nifi/
terraform init
```

### Terraform计划

运行Terraform计划以验证此执行创建的资源。

提供Route53托管区域主机名和相应的ACM证书；

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

输入`yes`以应用。

```
Outputs:

configure_kubectl = "aws eks --region us-west-2 update-kubeconfig --name nifi-on-eks"
```
### 验证部署

更新kubeconfig

```bash
aws eks --region us-west-2 update-kubeconfig --name nifi-on-eks
```

验证所有pod都在运行。

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

Apache NiFi仪表板可以在以下URL打开："https://nifi.example.com/nifi"

![Apache NiFi登录](../../../../../../docs/blueprints/streaming-platforms/img/nifi.png)

运行以下命令检索NiFi用户的密码，默认用户名为`admin`
```
aws secretsmanager get-secret-value --secret-id <terraform输出中的nifi_login_password_secret_name> --region <区域> | jq '.SecretString' --raw-output
```
![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-canvas.png)

### 监控
Apache Nifi可以使用PrometheusReportingTask报告的指标进行监控。默认情况下，JVM指标是禁用的，让我们通过点击右上角的汉堡图标（三条水平线）导航到控制器设置来启用JVM指标。

![Apache NiFi控制器设置](../../../../../../docs/blueprints/streaming-platforms/img/nifi-controller-settings.png)

接下来点击`REPORTING TASK`标签，然后点击`+`图标，在过滤器中搜索`PrometheusReportingTask`。选择`PrometheusReportingTask`并点击`ADD`按钮。

![Apache NiFi Prometheus报告](../../../../../../docs/blueprints/streaming-platforms/img/nifi-prometheus-reporting.png)

prometheus报告任务默认是停止的。

![Apache NiFi报告任务编辑](../../../../../../docs/blueprints/streaming-platforms/img/nifi-reporting-task-edit.png)

点击铅笔图标编辑任务，然后点击PROPERTIES标签。将`Send JVM metrics`设置为`true`并点击Apply。通过点击播放图标启动任务，并确保它处于运行状态。

![Apache NiFi报告任务True](../../../../../../docs/blueprints/streaming-platforms/img/nifi-reporting-task-true.png)

此蓝图使用`prometheus`和`grafana`创建监控堆栈，以便查看您的Apache NiFi集群。

```
aws secretsmanager get-secret-value --secret-id <terraform输出中的grafana_secret_name> --region <区域> | jq '.SecretString' --raw-output
```

运行以下命令并使用URL"http://localhost:8080" 打开Grafana仪表板。

```
kubectl port-forward svc/grafana -n grafana 8080:80
```

导入Apache NiFi [Grafana仪表板](https://grafana.com/grafana/dashboards/12314-nifi-prometheusreportingtask-dashboard/)

![Apache NiFi Grafana仪表板](../../../../../../docs/blueprints/streaming-platforms/img/nifi-grafana.png)
### 示例

#### 创建用于访问Amazon DynamoDB和AWS Kinesis的IAM策略

1. 创建AWS IAM角色：创建具有访问AWS Kinesis数据流权限的AWS IAM角色，并将此角色分配给托管Apache NiFi的AWS EKS集群。

2. 附加IAM策略：将策略附加到IAM角色，该策略将对Kinesis数据流的访问限制为只读，并启用EKS角色写入Amazon DynamoDB表的IAM策略。以下是示例策略：

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

#### 创建AWS Kinesis数据流
3. 创建AWS Kinesis数据流：登录AWS管理控制台，并在您想要收集数据的区域创建Kinesis数据流，或使用以下命令行创建一个。

```
aws kinesis create-stream --stream-name kds-stream-nifi-on-EKS
```

#### 创建Amazon DynamoDB表
4. 使用AWS控制台或命令行在同一AWS账户中创建Amazon DynamoDB。创建一个包含Amazon DynamoDb表信息的JSON文件，名为JSONSchemaDynamoDBTABLE.json

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

5. 执行命令行从JSON文件创建Amazon DynamoDB表。

```
aws dynamodb create-table --cli-input-json  JSONSchemaDynamoDBTABLE.json
```

6. 使用端点打开Apache NiFi on EKS UI，创建一个处理组，并将其命名为NifiStreamingExample。

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-1.png)

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-2.png)

7. 双击Nifi-on-EKS-process-group并进入该过程以创建数据流。从左上角拖动处理器图标，在搜索窗口中输入Kinesis，并选择ConsumeKinesisStream处理器。要创建Kinesis消费者，请点击ADD。

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-3.png)

8. 双击Kinesis处理器，选择properties标签，并填写以下配置信息。
   a. Amazon Kinesis Stream Name
   b. Application Name
   c. Region
   d. AWS Credentials Provider Service - 选择AWSCredentialsProviderControllerService并创建一个。


![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-4.png)

#### 创建AWS凭证设置

9. 使用AWS Credentials Provider Service设置AWS凭证以访问账户中的AWS资源。在此示例中，我们使用访问密钥和秘密密钥。<em>**注意**：还有其他选项，如基于IAM角色、假定角色选项来验证AWS资源。</em>

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-5.png)

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-6.png)

10. 从左上角拖动处理器图标，在搜索窗口中输入"dynamoDB"，并选择"PutDynamoDBRecord处理器。点击ADD创建Amazon DynamoDB写入器。使用以下字段配置处理器。

a. Record Reader - 更改为JSONTreeReader
b. AWS Credentials Provider Service - 选择之前创建的配置
c. Region
b. Table Name
d. Partition Key Field - 选择分区字段

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-7.png)
![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-8.png)
![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-9.png)

11. 悬停在Kinesis消费者上并将其拖到DynamoDB写入器。连接将建立，并创建成功队列。

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-10.png)

12. 为Kinesis Consumer和DynamoDB创建一个错误路由到漏斗。这是为了路由未处理、失败和成功的记录以进行进一步处理。注意：在Relationship标签下，您可以看到每个处理器的所有选项。对于DynamoDB写入器，成功应始终指向漏斗。

![Apache NiFi画布](../../../../../../docs/blueprints/streaming-platforms/img/nifi-screenshot-11.png)

13. 检查所有处理器是否都没有危险符号。右键点击网格并点击"运行数据流"。您可以开始看到数据流入。

## 清理

要清理您的环境，请按相反顺序销毁Terraform模块。

销毁Kubernetes附加组件、带有节点组的EKS集群和VPC

```bash
terraform destroy -target="module.eks_blueprints_kubernetes_addons" --auto-approve
terraform destroy -target="module.eks" --auto-approve
terraform destroy -target="module.vpc" --auto-approve
```

最后，销毁上述模块中不包含的任何其他资源

```bash
terraform destroy --auto-approve
```
