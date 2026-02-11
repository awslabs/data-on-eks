---
sidebar_position: 5
sidebar_label: EKS에서 Spark 관측성
---

import TaxiTripExec from './_taxi_trip_exec.md';

# EKS에서 Spark 관측성

## 소개
이 게시물에서는 EKS에서 Spark의 관측성(Observability)에 대해 알아봅니다. Spark History Server를 사용하여 Spark 애플리케이션 로그를 확인하고 Spark Web UI를 통해 Spark 작업 진행 상황을 확인합니다. Amazon Managed Service for Prometheus는 Spark 애플리케이션에서 생성된 메트릭을 수집하고 저장하는 데 사용되며, Grafana는 모니터링 사용 사례를 위한 대시보드를 구축하는 데 사용됩니다.

## 솔루션 배포
이전 Spark on Operator 예제를 재사용합니다. 리소스를 프로비저닝하려면 [이 링크](https://awslabs.github.io/data-on-eks/docs/data-analytics/spark-operator-yunikorn#deploying-the-solution) 를 따르세요.


## 데이터 및 py 스크립트 설정
spark-k8s-operator 아래의 예제 폴더로 이동하여 위에서 Terraform으로 생성한 S3 버킷에 데이터와 py 스크립트를 업로드하는 셸 스크립트를 실행합니다.
```bash
cd data-on-eks/analytics/terraform/spark-k8s-operator/examples/cluster-autoscaler/nvme-ephemeral-storage
```

<TaxiTripExec />

## Spark Web UI
Spark 애플리케이션을 제출하면 Spark 컨텍스트가 생성되며, 이상적으로는 애플리케이션 실행을 모니터링할 수 있는 [Spark Web UI](https://sparkbyexamples.com/spark/spark-web-ui-understanding/) 를 제공합니다. 모니터링에는 다음이 포함됩니다.
- 사용된 Spark 구성
- Spark 작업, 스테이지 및 태스크 세부 정보
- DAG 실행
- 드라이버 및 익스큐터 리소스 활용도
- 애플리케이션 로그 등 <br/>

애플리케이션이 처리를 완료하면 Spark 컨텍스트가 종료되고 Web UI도 함께 종료됩니다. 이미 완료된 애플리케이션의 모니터링을 보고 싶어도 볼 수 없습니다.

Spark Web UI를 사용해 보려면 nvme-ephemeral-storage.yaml에서 \<S3_BUCKET\>을 버킷 이름으로, \<JOB_NAME\>을 "nvme-taxi-trip"으로 업데이트합니다.

```bash
  kubectl apply -f nvme-ephemeral-storage.yaml
```

그런 다음 포트 포워드 명령을 실행하여 Spark 웹 서비스를 노출합니다.

```bash
kubectl port-forward po/taxi-trip 4040:4040 -nspark-team-a
```

그런 다음 브라우저를 열고 localhost:4040을 입력합니다. 아래와 같이 Spark 애플리케이션을 볼 수 있습니다.

![img.png](img/spark-web-ui.png)

## Spark History Server
위에서 언급했듯이 Spark Web UI는 Spark 작업이 완료되면 종료됩니다. 이때 Spark History Server가 필요합니다. Spark History Server는 완료된 모든 애플리케이션의 기록(이벤트 로그)과 런타임 정보를 유지하여 나중에 메트릭을 검토하고 애플리케이션을 모니터링할 수 있게 합니다.

이 예제에서는 S3 버킷에서 로그를 읽도록 Spark History Server를 설치했습니다. Spark 애플리케이션 yaml 파일에 다음 설정이 있는지 확인하세요:

```yaml
    sparkConf:
        "spark.hadoop.fs.s3a.aws.credentials.provider": "com.amazonaws.auth.InstanceProfileCredentialsProvider"
        "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
        "spark.eventLog.enabled": "true"
        "spark.eventLog.dir": "s3a://<your bucket>/logs/"
```

포트 포워드 명령을 실행하여 spark-history-server 서비스를 노출합니다.
```bash
kubectl port-forward services/spark-history-server 18085:80 -n spark-history-server
```

그런 다음 브라우저를 열고 localhost:18085를 입력합니다. 아래와 같이 Spark History Server를 볼 수 있습니다.
![img.png](img/spark-history-server.png)



## Prometheus
Spark 사용자는 Spark 드라이버 및 익스큐터에서 메트릭을 추출하기 위해 Spark 애플리케이션 yaml 파일에 다음 구성을 추가해야 합니다. 예제에서는 이미 nvme-ephemeral-storage.yaml에 추가되어 있습니다.

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

포트 포워드 명령을 실행하여 Prometheus 서비스를 노출합니다.
```bash
kubectl  port-forward service/prometheus-server   8080:80 -n prometheus
```

그런 다음 브라우저를 열고 localhost:8080을 입력합니다. 아래와 같이 Prometheus 서버를 볼 수 있습니다.
![img.png](img/prometheus-spark.png)

## Grafana
Grafana가 설치되었습니다. 포트 포워드를 사용하여 아래 명령으로 접근합니다.

# Grafana 비밀번호 가져오기

```bash
kubectl  port-forward service/grafana 8080:80 -n grafana
```

로그인 사용자 이름은 admin이고 비밀번호는 Secrets Manager에서 가져올 수 있습니다. 대시보드 ID: 7890으로 대시보드를 가져올 수 있습니다.

![img.png](img/spark-grafana-dashboard.png)
