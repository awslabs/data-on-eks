---
sidebar_position: 5
sidebar_label: Spark Observability on EKS
---

import TaxiTripExec from '../../../../../../docs/blueprints/data-analytics/_taxi_trip_exec.md';

# EKS 上的 Spark 可观察性

## 介绍
在这篇文章中，我们将学习 EKS 上 Spark 的可观察性。我们将使用 Spark History Server 来查看 Spark 应用程序日志，并通过 Spark Web UI 检查 Spark 作业进度。Amazon Managed Service for Prometheus 用于收集和存储 Spark 应用程序生成的指标，Grafana 用于构建监控用例的仪表板。

## 部署解决方案
我们将重用之前的 Spark on Operator 示例。请按照[此链接](https://awslabs.github.io/data-on-eks/docs/data-analytics/spark-operator-yunikorn#deploying-the-solution)配置资源

## 设置数据和 py 脚本
让我们导航到 spark-k8s-operator 下的一个示例文件夹，并运行 shell 脚本将数据和 py 脚本上传到上面 terraform 创建的 S3 存储桶。
```bash
cd data-on-eks/analytics/terraform/spark-k8s-operator/examples/cluster-autoscaler/nvme-ephemeral-storage
```

<TaxiTripExec />

## Spark Web UI
当您提交 Spark 应用程序时，会创建 Spark 上下文，理想情况下为您提供 [Spark Web UI](https://sparkbyexamples.com/spark/spark-web-ui-understanding/) 来监控应用程序的执行。监控包括以下内容。
- 使用的 Spark 配置
- Spark 作业、阶段和任务详细信息
- DAG 执行
- 驱动程序和执行器资源利用率
- 应用程序日志等等 <br/>

当您的应用程序完成处理时，Spark 上下文将被终止，您的 Web UI 也会终止。如果您想查看已完成应用程序的监控，我们无法做到这一点。

要尝试 Spark web UI，让我们在 nvme-ephemeral-storage.yaml 中用您的存储桶名称更新 \<S3_BUCKET\>，用 "nvme-taxi-trip" 更新 \<JOB_NAME\>

```bash
  kubectl apply -f nvme-ephemeral-storage.yaml
```

然后运行端口转发命令来公开 spark web 服务。

```bash
kubectl port-forward po/taxi-trip 4040:4040 -nspark-team-a
```

然后打开浏览器并输入 localhost:4040。您可以查看您的 spark 应用程序，如下所示。

![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-web-ui.png)
