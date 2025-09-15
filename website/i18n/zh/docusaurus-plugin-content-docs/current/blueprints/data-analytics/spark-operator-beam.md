---
sidebar_position: 5
sidebar_label: Apache Beam on EKS
hide_table_of_contents: true
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';

# 在 EKS 上使用 Spark 运行 Apache Beam 管道

[Apache Beam (Beam)](https://beam.apache.org/get-started/beam-overview/) 是一个灵活的编程模型，用于构建批处理和流数据处理管道。使用 Beam，开发人员可以编写一次代码并在各种执行引擎上运行，例如 *Apache Spark* 和 *Apache Flink*。这种灵活性允许组织在保持一致代码库的同时利用不同执行引擎的优势，减少管理多个代码库的复杂性并最小化供应商锁定的风险。

## EKS 上的 Beam

Kubernetes 的 Spark Operator 简化了 Apache Spark 在 Kubernetes 上的部署和管理。通过使用 Spark Operator，我们可以直接将 Apache Beam 管道作为 Spark 应用程序提交，并在 EKS 集群上部署和管理它们，利用 EKS 强大且托管的基础设施上的自动扩展和自愈能力等功能。

## 解决方案概述

在此解决方案中，我们将展示如何在带有 Spark Operator 的 EKS 集群上部署用 Python 编写的 Beam 管道。它使用来自 Apache Beam [github 仓库](https://github.com/apache/beam/tree/master/sdks/python)的示例管道。

![BeamOnEKS](../../../../../../docs/blueprints/data-analytics/img/spark-operator-beam.png)

## 部署 Beam 管道

<CollapsibleContent header={<h2><span>部署 Spark-Operator-on-EKS 解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)中，您将配置使用开源 Spark Operator 运行 Spark 作业所需的以下资源。

它将运行 Spark K8s Operator 的 EKS 集群部署到新的 VPC 中。

- 创建新的示例 VPC、2 个私有子网、2 个公有子网，以及 RFC6598 空间（100.64.0.0/10）中用于 EKS Pod 的 2 个子网。
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关
- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的），包含用于基准测试和核心服务的托管节点组，以及用于 Spark 工作负载的 Karpenter NodePool。
- 部署 Metrics server、Spark-operator、Apache Yunikorn、Karpenter、Grafana 和 Prometheus server。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆存储库。

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

如果 DOEKS_HOME 被取消设置，您可以始终从 data-on-eks 目录使用 `export DATA_ON_EKS=$(pwd)` 手动设置它。

导航到示例目录之一并运行 `install.sh` 脚本。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
chmod +x install.sh
./install.sh
```

现在创建一个 `S3_BUCKET` 变量，该变量保存安装期间创建的存储桶的名称。此存储桶将在后续示例中用于存储输出数据。如果 S3_BUCKET 被取消设置，您可以再次运行以下命令。

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>

### 步骤 1：构建包含 Spark 和 Beam SDK 的自定义 Docker 镜像

从官方 spark 基础镜像创建自定义 spark 运行时镜像，预装 Python 虚拟环境和 Apache Beam SDK。

- 查看示例 [Dockerfile](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/examples/beam/Dockerfile)
- 根据您的环境需要自定义 Dockerfile
- 构建 Docker 镜像并将镜像推送到 ECR

```sh
cd examples/beam
aws ecr create-repository --repository-name beam-spark-repo --region us-east-1
docker build . --tag ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/beam-spark-repo:eks-beam-image --platform linux/amd64,linux/arm64
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/beam-spark-repo:eks-beam-image
```

我们已经创建了一个 docker 镜像并发布在 ECR 中。

### 步骤 2：构建并打包带有依赖项的 Beam 管道

安装 python 3.11 后，创建 Python 虚拟环境并安装构建 Beam 管道所需的依赖项：

```sh
python3 -m venv build-environment && \
source build-environment/bin/activate && \
python3 -m pip install --upgrade pip && \
python3 -m pip install apache_beam==2.58.0 \
    s3fs \
    boto3

```

下载 [wordcount.py](https://raw.githubusercontent.com/apache/beam/master/sdks/python/apache_beam/examples/wordcount.py) 示例管道和示例输入文件。wordcount Python 示例演示了一个 Apache Beam 管道，包含以下阶段：读取文件、分割单词、映射、分组和求和单词计数，以及将输出写入文件。

```sh
curl -O https://raw.githubusercontent.com/apache/beam/master/sdks/python/apache_beam/examples/wordcount.py

curl -O https://raw.githubusercontent.com/cs109/2015/master/Lectures/Lecture15b/sparklect/shakes/kinglear.txt
```

将输入文本文件上传到 S3 存储桶。

```sh
aws s3 cp kinglear.txt s3://${S3_BUCKET}/
```

要在 Spark 上运行 Apache Beam Python 管道，您可以将管道及其所有依赖项打包到单个 jar 文件中。使用以下命令为 wordcount 管道创建包含所有参数的"fat" jar，而不实际执行管道：

```sh
python3 wordcount.py --output_executable_path=./wordcountApp.jar \ --runner=SparkRunner \ --environment_type=PROCESS \ --environment_config='{"command":"/opt/apache/beam/boot"}' \ --input=s3://${S3_BUCKET}/kinglear.txt \ --output=s3://${S3_BUCKET}/output.txt
```

将 jar 文件上传到 S3 存储桶以供 spark 应用程序使用。

```sh
aws s3 cp wordcountApp.jar s3://${S3_BUCKET}/app/
```

### 步骤 3：创建并运行管道作为 SparkApplication

在此步骤中，我们创建 SparkApplication 对象的清单文件，以将 Apache Beam 管道作为 Spark 应用程序提交。运行以下命令创建 BeamApp.yaml 文件，替换构建环境中的 ACCOUNT_ID 和 S3_BUCKET 值。

```sh
envsubst < beamapp.yaml > beamapp.yaml
```

此命令将替换文件 beamapp.yaml 中的环境变量。

### 步骤 4：执行 Spark 作业

应用 YAML 配置文件在您的 EKS 集群上创建 SparkApplication 以执行 Beam 管道：

```sh
kubectl apply -f beamapp.yaml
```

### 步骤 5：监控和查看管道作业

监控和查看管道作业
单词计数 Beam 管道可能需要几分钟才能执行。有几种方法可以监控其状态并查看作业详细信息。

1. 我们可以使用 Spark history server 检查正在运行的作业

我们使用 spark-k8s-operator 模式创建 EKS 集群，该集群已经安装并配置了 spark-history-server。运行以下命令开始端口转发，然后单击预览菜单并选择预览正在运行的应用程序：

```sh
kubectl port-forward svc/spark-history-server 8080:80 -n spark-history-server
```

打开新的浏览器窗口并转到此地址：http://127.0.0.1:8080/。

2. 作业成功完成后，大约 2 分钟内，包含在输入文本中找到的单词和每次出现次数的输出文件（output.txt-*）可以通过运行以下命令从 S3 存储桶下载，将输出复制到您的构建环境。

```sh
mkdir job_output &&  cd job_output
aws s3 sync s3://$S3_BUCKET/ . --include "output.txt-*" --exclude "kinglear*" --exclude app/*
```

输出如下所示：

```
...
particular: 3
wish: 2
Either: 3
benison: 2
Duke: 30
Contending: 1
say'st: 4
attendance: 1
...
```

<CollapsibleContent header={<h2><span>清理</span></h2>}>

:::caution
为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源
:::

## 删除 ECR 存储库

```bash
aws ecr delete-repository --repository-name beam-spark-repo --region us-east-1 --force
```

## 删除 EKS 集群

此脚本将使用 `-target` 选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>
