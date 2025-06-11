---
sidebar_position: 4
sidebar_label: EMR NVIDIA Spark-RAPIDS
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

# EMR on EKS NVIDIA RAPIDS Accelerator for Apache Spark

NVIDIA RAPIDS Accelerator for Apache Spark是一个强大的工具，它建立在NVIDIA CUDA®的功能之上 - CUDA是一个变革性的并行计算平台，旨在增强NVIDIA GPU架构上的计算过程。RAPIDS是由NVIDIA开发的项目，包含一套基于CUDA的开源库，从而实现GPU加速的数据科学工作流。

随着Spark 3的RAPIDS Accelerator的发明，NVIDIA成功地通过显著提高Spark SQL和DataFrame操作的效率，彻底改变了提取、转换和加载管道。通过合并RAPIDS cuDF库的功能和Spark分布式计算生态系统的广泛覆盖，RAPIDS Accelerator for Apache Spark提供了一个强大的解决方案来处理大规模计算。
此外，RAPIDS Accelerator库包含一个由UCX优化的高级shuffle，可以配置为支持GPU到GPU通信和RDMA功能，从而进一步提升其性能。

![替代文本](../../../../../../docs/blueprints/ai-ml/img/nvidia.png)

### EMR对NVIDIA RAPIDS Accelerator for Apache Spark的支持
Amazon EMR与NVIDIA RAPIDS Accelerator for Apache Spark的集成​ Amazon EMR on EKS现在扩展其支持，包括使用GPU实例类型与NVIDIA RAPIDS Accelerator for Apache Spark。随着人工智能(AI)和机器学习(ML)在数据分析领域的不断扩展，对快速和成本效益高的数据处理的需求越来越大，而GPU可以提供这些。NVIDIA RAPIDS Accelerator for Apache Spark使用户能够利用GPU的卓越性能，从而实现大幅度的基础设施成本节约。

### 特点
- 突出特点​ 在数据准备任务中体验性能提升，使您能够快速过渡到管道的后续阶段。这不仅加速了模型训练，还解放了数据科学家和工程师，使他们能够专注于优先任务。

- Spark 3确保端到端管道的无缝协调 - 从数据摄取，通过模型训练，到可视化。同一个GPU加速设置可以同时服务于Spark和机器学习或深度学习框架。这消除了对离散集群的需求，并为整个管道提供了GPU加速。

- Spark 3在Catalyst查询优化器中扩展了对列式处理的支持。RAPIDS Accelerator可以插入到这个系统中，加速SQL和DataFrame操作符。当查询计划被执行时，这些操作符可以利用Spark集群中的GPU来提高性能。

- NVIDIA引入了一种创新的Spark shuffle实现，旨在优化Spark任务之间的数据交换。这个shuffle系统建立在GPU加速的通信库上，包括UCX、RDMA和NCCL，这些库显著提高了数据传输率和整体性能。-


<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

:::warning
在部署此蓝图之前，重要的是要意识到与使用GPU实例相关的成本。该蓝图设置了八个g5.2xlarge GPU实例用于训练数据集，采用NVIDIA Spark-RAPIDS加速器。请确保相应地评估和规划这些成本。
:::

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/emr-spark-rapids)中，您将配置运行XGBoost Spark RAPIDS Accelerator作业所需的以下资源，使用[Fannie Mae的单户贷款表现数据](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data)。

此示例部署以下资源

- 创建一个新的示例VPC、2个私有子网和2个公共子网
- 为公共子网创建互联网网关，为私有子网创建NAT网关
- 创建EKS集群控制平面，带有公共端点（仅用于演示原因），以及核心托管节点组、Spark驱动程序节点组和用于ML工作负载的GPU Spot节点组。
- Spark驱动程序和Spark执行器GPU节点组使用Ubuntu EKS AMI
- 部署NVIDIA GPU Operator helm附加组件
- 部署Metrics server、Cluster Autoscaler、Karpenter、Grafana、AMP和Prometheus服务器。
- 启用EMR on EKS
  - 为数据团队创建两个命名空间（`emr-ml-team-a`，`emr-ml-team-b`）
  - 为两个命名空间创建Kubernetes角色和角色绑定（`emr-containers`用户）
  - 两个团队执行作业所需的IAM角色
  - 使用`emr-containers`用户和`AWSServiceRoleForAmazonEMRContainers`角色更新`AWS_AUTH`配置映射
  - 在作业执行角色和EMR托管服务账户的身份之间创建信任关系
  - 为`emr-ml-team-a`和`emr-ml-team-b`创建EMR虚拟集群和两者的IAM策略

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行`install.sh`脚本

```bash
cd data-on-eks/ai-ml/emr-spark-rapids/ && chmod +x install.sh
./install.sh
```

### 验证资源

验证Amazon EKS集群和Amazon Managed service for Prometheus

```bash
aws eks describe-cluster --name emr-spark-rapids
```

```bash
# 创建k8s配置文件以与EKS进行身份验证
aws eks --region us-west-2 update-kubeconfig --name emr-spark-rapids Cluster

kubectl get nodes # 输出显示EKS托管节点组节点

# 验证EMR on EKS命名空间`emr-ml-team-a`和`emr-ml-team-b`
kubectl get ns | grep emr-ml-team
```

```bash
kubectl get pods --namespace=gpu-operator

# GPU节点组运行一个节点的输出示例

    NAME                                                              READY   STATUS
    gpu-feature-discovery-7gccd                                       1/1     Running
    gpu-operator-784b7c5578-pfxgx                                     1/1     Running
    nvidia-container-toolkit-daemonset-xds6r                          1/1     Running
    nvidia-cuda-validator-j2b42                                       0/1     Completed
    nvidia-dcgm-exporter-vlttv                                        1/1     Running
    nvidia-device-plugin-daemonset-r5m7z                              1/1     Running
    nvidia-device-plugin-validator-hg78p                              0/1     Completed
    nvidia-driver-daemonset-6s9qv                                     1/1     Running
    nvidia-gpu-operator-node-feature-discovery-master-6f78fb7cbx79z   1/1     Running
    nvidia-gpu-operator-node-feature-discovery-worker-b2f6b           1/1     Running
    nvidia-gpu-operator-node-feature-discovery-worker-dc2pq           1/1     Running
    nvidia-gpu-operator-node-feature-discovery-worker-h7tpq           1/1     Running
    nvidia-gpu-operator-node-feature-discovery-worker-hkj6x           1/1     Running
    nvidia-gpu-operator-node-feature-discovery-worker-zjznr           1/1     Running
    nvidia-operator-validator-j7lzh                                   1/1     Running
```

</CollapsibleContent>
### 启动XGBoost Spark作业

#### 训练数据集
Fannie Mae的单户贷款表现数据拥有从2013年开始的全面数据集。它提供了对Fannie Mae单户贷款业务部分的信贷表现的宝贵见解。这个数据集旨在帮助投资者更好地了解Fannie Mae拥有或担保的单户贷款的信贷表现。

#### 步骤1：构建自定义Docker镜像

- 要从位于`us-west-2`的EMR on EKS ECR仓库中拉取Spark Rapids基础镜像，请登录：

```bash
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 895885662937.dkr.ecr.us-west-2.amazonaws.com
```

如果您位于不同的区域，请参考：这个[指南](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/docker-custom-images-tag.html.)。

- 要在本地构建您的Docker镜像，请使用以下命令：

使用提供的`Dockerfile`构建自定义Docker镜像。为镜像选择一个标签，如0.10。

:::info
请注意，构建过程可能需要一些时间，取决于您的网络速度。请记住，生成的镜像大小将约为`23.5GB`。
:::


```bash
cd ~/data-on-eks/ai-ml/emr-spark-rapids/examples/xgboost
docker build -t emr-6.10.0-spark-rapids-custom:0.10 -f Dockerfile .
```

- 将`<ACCOUNTID>`替换为您的AWS账户ID。使用以下命令登录到您的ECR仓库：

```bash
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <ACCOUNTID>.dkr.ecr.us-west-2.amazonaws.com
```

- 要将您的Docker镜像推送到您的ECR，请使用：

```bash
$ docker tag emr-6.10.0-spark-rapids-custom:0.10 <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/emr-6.10.0-spark-rapids-custom:0.10
$ docker push <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/emr-6.10.0-spark-rapids-custom:0.10
```

您可以在`步骤3`的作业执行期间使用此镜像。

### 步骤2：获取输入数据（Fannie Mae的单户贷款表现数据）

此数据集来源于[Fannie Mae的单户贷款表现数据](http://www.fanniemae.com/portal/funding-the-market/data/loan-performance-data.html)。所有权利由Fannie Mae持有。


1. 前往[Fannie Mae](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data)网站
2. 点击[单户贷款表现数据](https://datadynamics.fanniemae.com/data-dynamics/?&_ga=2.181456292.2043790680.1657122341-289272350.1655822609#/reportMenu;category=HP)
    - 如果您是首次使用该网站，请注册为新用户
    - 使用凭证登录
3. 选择[HP](https://datadynamics.fanniemae.com/data-dynamics/#/reportMenu;category=HP)
4. 点击`下载数据`并选择`单户贷款表现数据`
5. 您将找到一个基于年份和季度排序的`获取和表现`文件的表格列表。点击文件进行下载。您可以下载三年（2020年、2021年和2022年 - 每年4个文件，每个季度一个）的数据，这些数据将在我们的示例作业中使用。例如：2017Q1.zip
6. 解压下载的文件，将csv文件提取到您的本地机器。例如：2017Q1.csv
7. 仅将CSV文件复制到S3存储桶的`${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/spark-rapids-emr/input/fannie-mae-single-family-loan-performance/`下。下面的示例使用了三年的数据（每个季度一个文件，总共12个文件）。注意：`${S3_BUCKET}`和`${EMR_VIRTUAL_CLUSTER_ID}`值可以从Terraform输出中提取。

```
 aws s3 ls s3://emr-spark-rapids-<aws-account-id>-us-west-2/949wt7zuphox1beiv0i30v65i/spark-rapids-emr/input/fannie-mae-single-family-loan-performance/
    2023-06-24 21:38:25 2301641519 2000Q1.csv
    2023-06-24 21:38:25 9739847213 2020Q2.csv
    2023-06-24 21:38:25 10985541111 2020Q3.csv
    2023-06-24 21:38:25 11372073671 2020Q4.csv
    2023-06-23 16:38:36 9603950656 2021Q1.csv
    2023-06-23 16:38:36 7955614945 2021Q2.csv
    2023-06-23 16:38:36 5365827884 2021Q3.csv
    2023-06-23 16:38:36 4390166275 2021Q4.csv
    2023-06-22 19:20:08 2723499898 2022Q1.csv
    2023-06-22 19:20:08 1426204690 2022Q2.csv
    2023-06-22 19:20:08  595639825 2022Q3.csv
    2023-06-22 19:20:08  180159771 2022Q4.csv
```

### 步骤3：运行EMR Spark XGBoost作业

在这里，我们将使用一个辅助shell脚本来执行作业。此脚本需要用户输入。

此脚本将询问某些输入，您可以从Terraform输出中获取这些输入。请参见下面的示例。

```bash
cd ai-ml/emr-spark-rapids/examples/xgboost/ && chmod +x execute_spark_rapids_xgboost.sh
./execute_spark_rapids_xgboost.sh

# 示例输入如下所示
    Did you copy the fannie-mae-single-family-loan-performance data to S3 bucket(y/n): y
    Enter the customized Docker image URI: public.ecr.aws/o7d8v7g9/emr-6.10.0-spark-rapids:0.11
    Enter EMR Virtual Cluster AWS Region: us-west-2
    Enter the EMR Virtual Cluster ID: 949wt7zuphox1beiv0i30v65i
    Enter the EMR Execution Role ARN: arn:aws:iam::<ACCOUNTID>:role/emr-spark-rapids-emr-eks-data-team-a
    Enter the CloudWatch Log Group name: /emr-on-eks-logs/emr-spark-rapids/emr-ml-team-a
    Enter the S3 Bucket for storing PySpark Scripts, Pod Templates, Input data and Output data.<bucket-name>: emr-spark-rapids-<ACCOUNTID>-us-west-2
    Enter the number of executor instances (4 to 8): 8
```

验证pod状态

![替代文本](../../../../../../docs/blueprints/ai-ml/img/spark-rapids-pod-status.png)


:::info
请注意，第一次执行可能需要更长时间，因为它需要下载EMR作业Pod、驱动程序和执行器pod的镜像。每个pod可能需要长达8分钟的时间来下载Docker镜像。由于镜像缓存，后续运行应该更快（通常不到30秒）。
:::

### 步骤4：验证作业结果

- 登录以从CloudWatch日志或您的S3存储桶检查Spark驱动程序pod日志。

以下是日志文件的示例输出：

```
/emr-on-eks-logs/emr-spark-rapids/emr-ml-team-a
spark-rapids-emr/949wt7zuphox1beiv0i30v65i/jobs/0000000327fe50tosa4/containers/spark-0000000327fe50tosa4/spark-0000000327fe50tosa4-driver/stdout
```

以下是上述日志文件的示例输出：

    Raw Dataframe CSV Rows count : 215386024
    Raw Dataframe Parquet Rows count : 215386024
    ETL takes 222.34674382209778

    Training takes 95.90932035446167 seconds
    If features_cols param set, then features_col param is ignored.

    Transformation takes 63.999391317367554 seconds
    +--------------+--------------------+--------------------+----------+
    |delinquency_12|       rawPrediction|         probability|prediction|
    +--------------+--------------------+--------------------+----------+
    |             0|[10.4500541687011...|[0.99997103214263...|       0.0|
    |             0|[10.3076572418212...|[0.99996662139892...|       0.0|
    |             0|[9.81707763671875...|[0.99994546175003...|       0.0|
    |             0|[9.10498714447021...|[0.99988889694213...|       0.0|
    |             0|[8.81903457641601...|[0.99985212087631...|       0.0|
    +--------------+--------------------+--------------------+----------+
    only showing top 5 rows

    Evaluation takes 3.8372223377227783 seconds
    Accuracy is 0.996563056111921
### Fannie Mae单户贷款表现数据集的ML管道

**步骤1**：预处理和清洗数据集，处理缺失值、分类变量和其他数据不一致性。这可能涉及数据填充、独热编码和数据标准化等技术。

**步骤2**：从现有特征创建额外的特征，这些特征可能为预测贷款表现提供更有用的信息。例如，您可以提取诸如贷款价值比、借款人信用评分范围或贷款发放年份等特征。

**步骤3**：将数据集分为两部分：一部分用于训练XGBoost模型，一部分用于评估其性能。这使您能够评估模型对未见数据的泛化能力。

**步骤4**：将训练数据集输入XGBoost进行模型训练。XGBoost将分析贷款属性及其相应的贷款表现标签，以学习它们之间的模式和关系。目标是根据给定的特征预测贷款是否可能违约或表现良好。

**步骤5**：一旦模型训练完成，使用评估数据集来评估其性能。这涉及分析准确性、精确度、召回率或接收者操作特性曲线下面积(AUC-ROC)等指标，以衡量模型预测贷款表现的能力。

**步骤6**：如果性能不令人满意，您可以调整XGBoost超参数，如学习率、树深度或正则化参数，以提高模型的准确性或解决过拟合等问题。

**步骤7**：最后，使用训练和验证过的XGBoost模型，您可以对新的、未见过的贷款数据进行预测。这些预测可以帮助识别与贷款违约相关的潜在风险或评估贷款表现。


![替代文本](../../../../../../docs/blueprints/ai-ml/img/emr-spark-rapids-fannie-mae.png)

###  使用DCGM Exporter、Prometheus和Grafana进行GPU监控

可观测性在管理和优化GPU等硬件资源方面起着至关重要的作用，特别是在GPU利用率高的机器学习工作负载中。实时监控GPU使用情况、识别趋势和检测异常的能力可以显著影响性能调优、故障排除和高效资源利用。

[NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator)在GPU可观测性中扮演关键角色。它自动部署在Kubernetes上运行GPU工作负载所需的组件。其中一个组件，[DCGM (Data Center GPU Manager) Exporter](https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/latest/index.html)，是一个开源项目，它导出可被Prometheus（一个领先的开源监控解决方案）摄取的GPU指标格式。这些指标包括GPU温度、内存使用情况、GPU利用率等。DCGM Exporter允许您按每个GPU监控这些指标，提供对GPU资源的细粒度可见性。

NVIDIA GPU Operator结合DCGM Exporter，将GPU指标导出到Prometheus服务器。通过其灵活的查询语言，Prometheus允许您切片和分析数据，以生成对资源使用模式的见解。

然而，Prometheus并非设计用于长期数据存储。这就是[Amazon Managed Service for Prometheus (AMP)](https://aws.amazon.com/prometheus/)发挥作用的地方。它提供了一个完全托管、安全且可扩展的Prometheus服务，使您能够轻松地大规模分析操作数据，而无需管理底层基础设施。

可视化这些指标并创建信息丰富的仪表板是Grafana擅长的领域。Grafana是一个开源的监控和可观测性平台，提供丰富的可视化功能，以直观地表示收集的指标。当与Prometheus结合使用时，Grafana可以以用户友好的方式显示DCGM Exporter收集的GPU指标。

NVIDIA GPU Operator配置为将指标导出到Prometheus服务器，然后Prometheus将这些指标远程写入Amazon Managed Prometheus (AMP)。作为用户，您可以登录作为蓝图一部分部署的Grafana WebUI，并添加AMP作为数据源。之后，您可以导入开源[GPU监控仪表板](https://grafana.com/grafana/dashboards/12239-nvidia-dcgm-exporter-dashboard/)，该仪表板以易于理解的格式呈现GPU指标，便于实时性能监控和资源优化。

1. **NVIDIA GPU Operator**：安装在您的Kubernetes集群上，NVIDIA GPU Operator负责管理GPU资源的生命周期。它在每个配备GPU的节点上部署NVIDIA驱动程序和DCGM Exporter。
2. **DCGM Exporter**：DCGM Exporter在每个节点上运行，收集GPU指标并将其暴露给Prometheus。
3. **Prometheus**：Prometheus是一个时间序列数据库，从各种来源收集指标，包括DCGM Exporter。它定期从导出器拉取指标并存储它们。在此设置中，您将配置Prometheus将收集的指标远程写入AMP。
4. **Amazon Managed Service for Prometheus (AMP)**：AMP是AWS提供的完全托管的Prometheus服务。它负责Prometheus数据的长期存储、可扩展性和安全性。
5. **Grafana**：Grafana是一个可视化工具，可以查询AMP获取收集的指标，并在信息丰富的仪表板上显示它们。

在这个蓝图中，我们利用DCGM将GPU指标写入Prometheus和Amazon Managed Prometheus (AMP)。要验证GPU指标，您可以通过运行以下命令使用Grafana：

```bash
kubectl port-forward svc/grafana 3000:80 -n grafana
``

使用`admin`作为用户名登录Grafana，并使用以下AWS CLI命令从Secrets Manager检索密码：

```bash
aws secretsmanager get-secret-value --secret-id emr-spark-rapids-grafana --region us-west-2
```

登录后，将AMP数据源添加到Grafana并导入开源GPU监控仪表板。然后，您可以探索指标并使用Grafana仪表板可视化它们，如下面的截图所示。

![替代文本](../../../../../../docs/blueprints/ai-ml/img/gpu-dashboard.png)

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/emr-spark-rapids/ && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源
:::
