---
sidebar_position: 5
sidebar_label: EKS上的Spark可观测性
---

import TaxiTripExec from '../../../../../../docs/blueprints/data-analytics/_taxi_trip_exec.md';

# EKS上的可观测性Spark

## 介绍
在本文中，我们将学习EKS上Spark的可观测性。我们将使用Spark History Server查看Spark应用程序日志并通过Spark Web UI检查Spark作业进度。Amazon Managed Service for Prometheus用于收集和存储Spark应用程序生成的指标，Grafana用于构建监控用例的仪表板。

## 部署解决方案
我们将重用之前的Spark on Operator示例。请按照[此链接](https://awslabs.github.io/data-on-eks/docs/data-analytics/spark-operator-yunikorn#deploying-the-solution)配置资源


## 设置数据和py脚本
让我们导航到spark-k8s-operator下的一个示例文件夹，并运行shell脚本将数据和py脚本上传到上面terraform创建的S3存储桶。
```bash
cd data-on-eks/analytics/terraform/spark-k8s-operator/examples/cluster-autoscaler/nvme-ephemeral-storage
```

<TaxiTripExec />

## Spark Web UI
当您提交Spark应用程序时，会创建Spark上下文，它理想情况下为您提供[Spark Web UI](https://sparkbyexamples.com/spark/spark-web-ui-understanding/)来监控应用程序的执行。监控包括以下内容。
- 使用的Spark配置
- Spark作业、阶段和任务详情
- DAG执行
- 驱动程序和执行器资源利用率
- 应用程序日志等等 <br/>

当您的应用程序完成处理后，Spark上下文将被终止，因此您的Web UI也会终止。如果您想查看已完成应用程序的监控，我们无法做到。

要尝试Spark web UI，让我们在nvme-ephemeral-storage.yaml中将\<S3_BUCKET\>更新为您的存储桶名称，将\<JOB_NAME\>更新为"nvme-taxi-trip"

```bash
  kubectl apply -f nvme-ephemeral-storage.yaml
```

然后运行端口转发命令来暴露spark web服务。

```bash
kubectl port-forward po/taxi-trip 4040:4040 -nspark-team-a
```

然后打开浏览器并输入localhost:4040。您可以像下面这样查看您的spark应用程序。

![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-web-ui.png)

## Spark History Server
如上所述，一旦spark作业完成，spark web UI将被终止。这就是Spark history Server发挥作用的地方，它保存所有已完成应用程序的历史记录（事件日志）及其运行时信息，使您能够稍后查看指标和监控应用程序。

在此示例中，我们安装了Spark history Server以从S3存储桶读取日志。在您的spark应用程序yaml文件中，确保您有以下设置：

```yaml
    sparkConf:
        "spark.hadoop.fs.s3a.aws.credentials.provider": "com.amazonaws.auth.InstanceProfileCredentialsProvider"
        "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
        "spark.eventLog.enabled": "true"
        "spark.eventLog.dir": "s3a://<your bucket>/logs/"
```

运行端口转发命令来暴露spark-history-server服务。
```bash
kubectl port-forward services/spark-history-server 18085:80 -n spark-history-server
```

然后打开浏览器并输入localhost:18085。您可以像下面这样查看您的spark history server。
![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-history-server.png)



## Prometheus
Spark用户必须在spark应用程序yaml文件中添加以下配置，以从Spark驱动程序和执行器中提取指标。在示例中，它们已经添加到nvme-ephemeral-storage.yaml中。

```yaml
    "spark.ui.prometheus.enabled": "true"
    "spark.executor.processTreeMetrics.enabled": "true"
    "spark.kubernetes.driver.annotation.prometheus.io/scrape": "true"
    "spark.kubernetes.driver.annotation.prometheus.io/path": "/metrics/executors/prometheus/"
    "spark.kubernetes.driver.annotation.prometheus.io/port": "4040"
    "spark.kubernetes.driver.service.annotation.prometheus.io/scrape": "true"
    "spark.kubernetes.driver.service.annotation.prometheus.io/path": "/metrics/driver/prometheus/"
    "spark.kubernetes.driver.service.annotation.prometheus.io/port": "4040"
    "spark.metrics.conf.*.sink.prometheusServlet.class": "org.apache.spark.metrics.sink.PrometheusServlet"
    "spark.metrics.conf.*.sink.prometheusServlet.path": "/metrics/driver/prometheus/"
    "spark.metrics.conf.master.sink.prometheusServlet.path": "/metrics/master/prometheus/"
    "spark.metrics.conf.applications.sink.prometheusServlet.path": "/metrics/applications/prometheus/"
```

运行端口转发命令来暴露prometheus服务。
```bash
kubectl  port-forward service/prometheus-server   8080:80 -n prometheus
```

然后打开浏览器并输入localhost:8080。您可以像下面这样查看您的prometheus服务器。
![img.png](../../../../../../docs/blueprints/data-analytics/img/prometheus-spark.png)

## Grafana
已安装Grafana。使用以下命令通过端口转发访问。

# 获取grafana密码

```bash
kubectl  port-forward service/grafana 8080:80 -n grafana
```

登录用户名是admin，密码可以从secrets manager获取。您可以导入ID为7890的仪表板。

![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-grafana-dashboard.png)
