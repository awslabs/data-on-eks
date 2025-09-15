---
sidebar_position: 5
sidebar_label: Spark Observability on EKS
---

import TaxiTripExec from './_taxi_trip_exec.md';

# EKS 上的 Spark 可观测性

## 介绍
在这篇文章中，我们将学习 EKS 上 Spark 的可观测性。我们将使用 Spark History Server 来查看 Spark 应用程序日志，并通过 Spark Web UI 检查 Spark 作业进度。Amazon Managed Service for Prometheus 用于收集和存储 Spark 应用程序生成的指标，Grafana 用于构建监控用例的仪表板。

## 部署解决方案
我们将重用之前的 Spark on Operator 示例。请按照[此链接](https://awslabs.github.io/data-on-eks/docs/data-analytics/spark-operator-yunikorn#deploying-the-solution)来配置资源

## 设置数据和 py 脚本
让我们导航到 spark-k8s-operator 下的一个示例文件夹，并运行 shell 脚本将数据和 py 脚本上传到上面 terraform 创建的 S3 存储桶。
```bash
cd data-on-eks/analytics/terraform/spark-k8s-operator/examples/cluster-autoscaler/nvme-ephemeral-storage
```

<TaxiTripExec />

## Spark Web UI
当您提交 Spark 应用程序时，会创建 Spark 上下文，它理想情况下为您提供 [Spark Web UI](https://sparkbyexamples.com/spark/spark-web-ui-understanding/) 来监控应用程序的执行。监控包括以下内容：
- 使用的 Spark 配置
- Spark 作业、阶段和任务详细信息
- DAG 执行
- 驱动程序和执行器资源利用率
- 应用程序日志等等 <br/>

当您的应用程序完成处理后，Spark 上下文将被终止，您的 Web UI 也会被终止。如果您想查看已完成应用程序的监控，我们无法做到这一点。

要尝试 Spark web UI，让我们在 nvme-ephemeral-storage.yaml 中将 \<S3_BUCKET\> 更新为您的存储桶名称，将 \<JOB_NAME\> 更新为 "nvme-taxi-trip"

```bash
  kubectl apply -f nvme-ephemeral-storage.yaml
```

然后运行端口转发命令来暴露 spark web 服务。

```bash
kubectl port-forward po/taxi-trip 4040:4040 -nspark-team-a
```

然后打开浏览器并输入 localhost:4040。您可以查看您的 spark 应用程序，如下所示。

![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-web-ui.png)

## Spark History Server
如上所述，一旦 spark 作业完成，spark web UI 将被终止。这就是 Spark history Server 发挥作用的地方，它保留所有已完成应用程序的历史记录（事件日志）及其运行时信息，允许您稍后查看指标和监控应用程序。

在此示例中，我们安装了 Spark history Server 来从 S3 存储桶读取日志。在您的 spark 应用程序 yaml 文件中，确保您有以下设置：

```yaml
    sparkConf:
        "spark.hadoop.fs.s3a.aws.credentials.provider": "com.amazonaws.auth.InstanceProfileCredentialsProvider"
        "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
        "spark.eventLog.enabled": "true"
        "spark.eventLog.dir": "s3a://<your bucket>/logs/"
```

运行端口转发命令来暴露 spark-history-server 服务。
```bash
kubectl port-forward services/spark-history-server 18085:80 -n spark-history-server
```

然后打开浏览器并输入 localhost:18085。您可以查看您的 spark history server，如下所示。
![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-history-server.png)

## Prometheus
Spark 用户必须将以下配置添加到 spark 应用程序 yaml 文件中，以从 Spark 驱动程序和执行器中提取指标。在示例中，它们已经添加到 nvme-ephemeral-storage.yaml 中。

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

运行端口转发命令来暴露 prometheus 服务。
```bash
kubectl  port-forward service/prometheus-server   8080:80 -n prometheus
```

然后打开浏览器并输入 localhost:8080。您可以查看您的 prometheus 服务器，如下所示。
![img.png](../../../../../../docs/blueprints/data-analytics/img/prometheus-spark.png)

## Grafana
Grafana 已安装。使用以下命令通过端口转发访问。

# 获取 grafana 密码

```bash
kubectl  port-forward service/grafana 8080:80 -n grafana
```

登录用户名是 admin，密码可以从 secrets manager 获取。您可以使用 ID: 7890 导入仪表板。

![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-grafana-dashboard.png)
