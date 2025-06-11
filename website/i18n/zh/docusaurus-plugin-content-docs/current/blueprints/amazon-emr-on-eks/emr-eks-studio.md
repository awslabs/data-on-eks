---
sidebar_position: 6
sidebar_label: EMR on EKS Data Platform with AWS CDK
---

:::danger
**弃用通知**

此蓝图将于**2024年10月27日**被弃用并最终从此GitHub仓库中移除。不会修复任何错误，也不会添加新功能。弃用的决定基于对此蓝图的需求和兴趣不足，以及难以分配资源维护一个没有被任何用户或客户积极使用的蓝图。

如果您在生产环境中使用此蓝图，请将自己添加到[adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md)页面并在仓库中提出问题。这将帮助我们重新考虑并可能保留并继续维护该蓝图。否则，您可以制作本地副本或使用现有标签访问它。
:::

# EMR on EKS Data Platform with AWS CDK

在本文档中，我们将向您展示如何使用AWS CDK和[Analytics Reference Architecture](https://aws.amazon.com/blogs/opensource/adding-cdk-constructs-to-the-aws-analytics-reference-architecture/) (ARA)库来部署端到端数据分析平台。该平台将允许您在由EMR on EKS支持的EMR Studio的Jupyter笔记本中运行Spark交互式会话，并使用EMR on EKS运行Spark作业。下面的架构显示了您将使用CDK和ARA库部署的基础设施。

![emr-eks-studio-ara-architecture](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-studio-cdk-ara.png)

## [Analytics Reference Architecture](https://aws.amazon.com/blogs/opensource/adding-cdk-constructs-to-the-aws-analytics-reference-architecture/)

AWS Analytics Reference Architecture (ARA)在AWS CDK库中公开了一组可重用的核心组件，目前可用于Typescript和Python。该库包含AWS CDK构造(L3)，可用于在演示、原型、概念验证和端到端参考架构中快速配置分析解决方案。ARA库的API定义在[这里](https://constructs.dev/packages/aws-analytics-reference-architecture/v/2.4.11?lang=typescript)。

在我们的案例中，该库帮助您部署针对在EKS上运行的Apache Spark进行了优化的基础设施，利用EMR on EKS。该基础设施将开箱即用地为您提供pod协同定位以减少网络流量，在单个可用区中部署节点组以减少shuffle期间的跨可用区流量，为EMR on EKS使用专用实例，为内存密集型作业使用优化实例，为非关键作业使用竞价和按需实例，为关键作业使用按需实例。

## 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html#getting_started_install)

## 解决方案

要部署数据平台，我们将使用`Analytics Reference Architecture`中的一个示例。该示例位于您将在下面克隆的仓库中的`examples/emr-eks-app`目录中。

克隆仓库

```bash
git clone https://github.com/aws-samples/aws-analytics-reference-architecture.git
```

此解决方案将部署以下内容：

- EKS集群和一组节点组：

- 名为tooling的托管节点组，用于运行系统关键pod。例如，Cluster Autoscaler、CoreDNS、EBS CSI Driver..
- 三个名为critical的托管节点组，用于关键作业，每个在一个可用区，此节点组使用按需实例
- 三个名为non-critical的托管节点组，用于非关键作业，每个在一个可用区，此节点组使用竞价实例
- 三个名为notebook-driver的托管节点组，用于非关键作业，每个在一个可用区，此节点组使用按需实例以获得稳定的驱动程序。
- 三个名为notebook-executor的托管节点组，用于非关键作业，每个在一个可用区，此节点组为执行器使用竞价实例。

- 启用EKS集群与EMR on EKS服务一起使用
- 名为`batchjob`的EMR虚拟集群，用于提交作业
- 名为`emrvcplatform`的EMR虚拟集群，用于提交作业
- 名为`platform`的EMR Studio
- 一个名为`platform-myendpoint`的`托管端点`，用于您将在EMR Studio中创建的Jupyter笔记本
- 使用EMR on EKS `start-job-run`提交作业时使用的[执行角色](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/iam-execution-role.html)
- 与托管端点一起使用的执行角色。
- 存储在名为"EKS-CLUSTER-NAME-emr-eks-assets-ACCOUNT-ID-REGION"的S3存储桶中的pod模板

### 自定义

上述基础设施在`emr-eks-app/lib/emr-eks-app-stack.ts`中定义。如果您想自定义它，可以更改其中的值。例如，您可以选择不创建用于`作业`的默认节点组，在这种情况下，您可以在`EmrEksCluster`中将`defaultNodeGroups`参数设置为`false`。您还可以调用`addEmrEksNodegroup`方法来定义具有特定标签、实例或污点的自己的节点组。`addEmrEksNodegroup`方法在[这里](https://constructs.dev/packages/aws-analytics-reference-architecture/v/2.4.11/api/EmrEksCluster?lang=typescript#addEmrEksNodegroup)定义。

您还可以通过`createExecutionRole` [方法](https://constructs.dev/packages/aws-analytics-reference-architecture/v/2.4.11/api/EmrEksCluster?lang=typescript#createExecutionRole)创建自己的执行角色，或创建托管端点将其附加到您在ARA库外部部署的EMR Studio。

为了简化此示例，我们对`EMR Studio`使用带有IAM用户的IAM身份验证。如果您想使用`AWS IAM Identity Center`中的用户，可以在`NotebookPlatform`构造中更改`studioAuthMode`。下面您可以看到需要更改的代码片段。

```ts
const notebookPlatform = new ara.NotebookPlatform(this, 'platform-notebook', {
emrEks: emrEks,
eksNamespace: 'dataanalysis',
studioName: 'platform',
studioAuthMode: ara.StudioAuthMode.IAM,
});
```

### 部署

在运行解决方案之前，您**必须**更改`lib/emr-eks-app-stack.ts`中`EmrEksCluster`的`props`对象的`eksAdminRoleArn`。此角色允许您管理EKS集群，并且应该至少允许IAM操作`eks:AccessKubernetesApi`。您还需要更改`NotebookPlatform`构造的`addUser`方法中的`identityName`。identityName**必须**是您使用的有效IAM用户名。下面您可以看到需要更改的代码片段。

```ts
notebookPlatform.addUser([{
identityName:'',
notebookManagedEndpoints: [{
emrOnEksVersion: 'emr-6.8.0-latest',
executionPolicy: emrEksPolicy,
managedEndpointName: 'myendpoint'
}],
}]);
```

最后，如果您想处理您拥有的S3存储桶中的数据，您还应该更新传递给`createExecutionRole`的IAM策略。

导航到示例目录之一并运行`cdk synth --profile YOUR-AWS-PROFILE`

```bash
cd examples/emr-eks-app
npm install
cdk synth --profile YOUR-AWS-PROFILE
```

合成完成后，您可以使用以下命令部署基础设施：

```bash
cdk deploy
```

在部署结束时，您将看到如下输出：

![ara-cdk-output](../../../../../../docs/blueprints/amazon-emr-on-eks/img/cdk-deploy-result.png)

在输出中，您将找到具有Kubernetes上Spark最佳实践（如`dynamicAllocation`和`pod collocation`）的作业示例配置。

### 作业提交

在此示例中，我们将使用`crittical-job`作业配置提交一个作业，该作业将使用Spark分发中的一部分计算`pi`。
要提交作业，我们将使用AWS CLI的`start-job-run`命令。

在运行下面的命令之前，请确保更新以下参数，使用您自己的部署创建的参数。

    - \<CLUSTER-ID\> – EMR虚拟集群ID，您从AWS CDK输出中获取
    - \<SPARK-JOB-NAME\> – 您的Spark作业名称
    - \<ROLE-ARN\> – 您创建的执行角色，您从AWS CDK输出中获取
    - \<S3URI-CRITICAL-DRIVER\> – 驱动程序pod模板的Amazon S3 URI，您从AWS CDK输出中获取
    - \<S3URI-CRITICAL-EXECUTOR\> – 执行器pod模板的Amazon S3 URI，您从AWS CDK输出中获取
    - \<Log_Group_Name\> – 您的CloudWatch日志组名称
    - \<Log_Stream_Prefix\> – 您的CloudWatch日志流前缀

<details>
    <summary>start-job-run命令的AWS CLI</summary>

    ```bash
    aws emr-containers start-job-run \
        --virtual-cluster-id CLUSTER-ID\
        --name=SPARK-JOB-NAME\
        --execution-role-arn ROLE-ARN \
        --release-label emr-6.8.0-latest \
        --job-driver '{
        "sparkSubmitJobDriver":{
            "entryPoint": "local:///usr/lib/spark/examples/src/main/python/pi.py"
        }
    }' \
    --configuration-overrides '{
        "applicationConfiguration": [
        {
            "classification": "spark-defaults",
            "properties": {
                "spark.hadoop.hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory",
                "spark.sql.catalogImplementation": "hive",
                "spark.dynamicAllocation.enabled":"true",
                "spark.dynamicAllocation.minExecutors": "8",
                "spark.dynamicAllocation.maxExecutors": "40",
                "spark.kubernetes.allocation.batch.size": "8",
                "spark.executor.cores": "8",
                "spark.kubernetes.executor.request.cores": "7",
                "spark.executor.memory": "28G",
                "spark.driver.cores": "2",
                "spark.kubernetes.driver.request.cores": "2",
                "spark.driver.memory": "6G",
                "spark.dynamicAllocation.executorAllocationRatio": "1",
                "spark.dynamicAllocation.shuffleTracking.enabled": "true",
                "spark.dynamicAllocation.shuffleTracking.timeout": "300s",
                "spark.kubernetes.driver.podTemplateFile": "s3://EKS-CLUSTER-NAME-emr-eks-assets-ACCOUNT-ID-REGION/EKS-CLUSTER-NAME/pod-template/critical-driver.yaml",
                "spark.kubernetes.executor.podTemplateFile": "s3://EKS-CLUSTER-NAME-emr-eks-assets-ACCOUNT-ID-REGION/EKS-CLUSTER-NAME/pod-template/critical-executor.yaml"
            }
        }
        ],
        "monitoringConfiguration": {
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "Log_Group_Name",
                "logStreamNamePrefix": "Log_Stream_Prefix"
            }
        }
    }'
    ```
</details>

验证作业执行

```bash
kubectl get pods --namespace=batchjob -w
```

### 交互式会话

要使用交互式会话，您应该使用在`cdk deploy`结束时提供给您的URL登录到EMR Studio实例。
此链接的形式为`https://es-xxxxx/emrstudio-prod-REGION.amazonaws.com`。
点击链接后，您将看到一个登录页面，您**必须**使用提供给`addUser`方法的用户名登录。登录后，您应该按照以下步骤操作。

1. 创建工作区，这将启动Jupyter笔记本
2. 连接到Jupter笔记本
3. 附加到虚拟集群，这将具有以下名称"emrvcplatform"，并选择名为"platform-myendpoint"的端点
4. 打开笔记本并选择PySpark内核
5. 您现在已准备好使用在EMR on EKS上运行的Spark分析您的数据。

## 清理

要清理您的环境，您可以调用下面的命令。这将销毁带有节点组和VPC的EKS集群

```bash
cdk destroy
```

:::caution

为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源
:::
