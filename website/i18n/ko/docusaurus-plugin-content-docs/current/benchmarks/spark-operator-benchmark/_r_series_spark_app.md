```yaml
apiVersion: "sparkoperator.k8s.io/v1beta2"
kind: SparkApplication
metadata:
  name: tpcds-benchmark-1tb-ebs # 각 테스트에 대해 인스턴스 유형 등으로 변경,
  namespace: spark-team-a
spec:
  # YuniKorn 이슈가 해결될 때까지 임시로 주석 처리; 기본 Kubernetes 스케줄러로 폴백
  # batchScheduler: yunikorn
  # batchSchedulerOptions:
  #   queue: root.default
  type: Scala
  mode: cluster
  image: public.ecr.aws/data-on-eks/spark3.5.3-scala2.12-java17-python3-ubuntu-tpcds:v2
  imagePullPolicy: IfNotPresent
  sparkVersion: 3.5.3
  mainClass: com.amazonaws.eks.tpcds.BenchmarkSQL
  mainApplicationFile: local:///opt/spark/examples/jars/eks-spark-benchmark-assembly-1.0.jar
  arguments:
    # TPC-DS 데이터 위치
    - "s3a://<S3_BUCKET>/TPCDS-TEST-1TB"
    # 결과 위치
    - "s3a://<S3_BUCKET>/TPCDS-TEST-1T-RESULT"
    # docker 이미지 내 키트 경로
    - "/opt/tpcds-kit/tools"
    # 데이터 형식
    - "parquet"
    # 스케일 팩터 (GB)
    - "1000" # 데모용으로 3000에서 100gb로 변경
    # 반복 횟수
    - "1"
    # hive 테이블로 쿼리 최적화
    - "false"
    # 쿼리 필터, 비어 있으면 모두 실행 - "q98-v2.4,q99-v2.4,ss_max-v2.4,q95-v2.4"
    - ""
    # 로깅을 WARN으로 설정
    - "true"
  sparkConf:
    # Prometheus용 Spark 메트릭 노출
    "spark.ui.prometheus.enabled": "true"
    "spark.executor.processTreeMetrics.enabled": "true"
    "spark.metrics.conf.*.sink.prometheusServlet.class": "org.apache.spark.metrics.sink.PrometheusServlet"
    "spark.metrics.conf.driver.sink.prometheusServlet.path": "/metrics/driver/prometheus/"
    "spark.metrics.conf.executor.sink.prometheusServlet.path": "/metrics/executors/prometheus/"

    # Spark 이벤트 로그
    "spark.eventLog.enabled": "true"
    "spark.eventLog.dir": "s3a://<S3_BUCKET>/spark-event-logs"
    "spark.eventLog.rolling.enabled": "true"
    "spark.eventLog.rolling.maxFileSize": "64m"

    "spark.network.timeout": "2000s"
    "spark.executor.heartbeatInterval": "300s"
    # AQE
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.localShuffleReader.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.adaptive.skewJoin.enabled": "true"
    "spark.kubernetes.executor.podNamePrefix": "benchmark-exec-ebs"
   # S3 최적화
    # "spark.hadoop.fs.s3a.aws.credentials.provider": "com.amazonaws.auth.WebIdentityTokenCredentialsProvider" # 유지 관리 모드의 AWS SDK V1 사용
    "spark.hadoop.fs.s3a.aws.credentials.provider.mapping": "com.amazonaws.auth.WebIdentityTokenCredentialsProvider=software.amazon.awssdk.auth.credentials.WebIdentityTokenFileCredentialsProvider"
    "spark.hadoop.fs.s3a.aws.credentials.provider": "software.amazon.awssdk.auth.credentials.WebIdentityTokenFileCredentialsProvider"  # AWS SDK V2 https://hadoop.apache.org/docs/stable/hadoop-aws/tools/hadoop-aws/aws_sdk_upgrade.html
    "spark.hadoop.fs.s3.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
    "spark.hadoop.fs.s3a.fast.upload": "true"
    "spark.hadoop.fs.s3a.path.style.access": "true"
    "spark.hadoop.fs.s3a.fast.upload.buffer": "disk"
    "spark.hadoop.fs.s3a.buffer.dir": "/tmp/s3a"
    "spark.hadoop.fs.s3a.multipart.size": "128M" # 대용량 파일에 적합
    "spark.hadoop.fs.s3a.multipart.threshold": "256M"
    "spark.hadoop.fs.s3a.threads.max": "50"
    "spark.hadoop.fs.s3a.connection.maximum": "200"

    "spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version": "2"
    "spark.executor.defaultJavaOptions": "-verbose:gc -XX:+UseParallelGC -XX:InitiatingHeapOccupancyPercent=70"
    # "spark.hadoop.fs.s3a.readahead.range": "256K"

    # -----------------------------------------------------
    # 이 블록은 다음과 같은 오류가 발생할 때 매우 중요합니다
    #     Exception in thread \"main\" io.fabric8.kubernetes.client.KubernetesClientException: An error has occurred
    #     Caused by: java.net.SocketTimeoutException: timeout
    # spark.kubernetes.local.dirs.tmpfs: "true" # 자세한 내용은 https://spark.apache.org/docs/latest/running-on-kubernetes.html#using-ram-for-local-storage 참조
    spark.kubernetes.submission.connectionTimeout: "120000" # 밀리초
    spark.kubernetes.submission.requestTimeout: "120000"
    spark.kubernetes.driver.connectionTimeout: "120000"
    spark.kubernetes.driver.requestTimeout: "120000"
    # spark.kubernetes.allocation.batch.size: "20" # 기본값 5이지만 클러스터 크기에 따라 조정
    # -----------------------------------------------------
    # S3 최적화
    "spark.hadoop.fs.s3a.multipart.size": "67108864"           # S3 업로드용 64 MB 파트 크기
    "spark.hadoop.fs.s3a.threads.max": "40"                     # 최적화된 처리량을 위해 S3 스레드 제한
    "spark.hadoop.fs.s3a.connection.maximum": "100"             # S3용 최대 연결 설정

    # 데이터 쓰기 및 셔플 튜닝
    "spark.shuffle.file.buffer": "1m"                           # 더 나은 디스크 I/O를 위해 셔플 버퍼 증가
    "spark.reducer.maxSizeInFlight": "48m"                      # 전송 중 데이터용 리듀서 버퍼 크기 증가

    # 선택 사항: 멀티파트 업로드 임계값 튜닝
    "spark.hadoop.fs.s3a.multipart.purge": "true"               # 실패한 멀티파트 업로드 자동 정리
    "spark.hadoop.fs.s3a.multipart.threshold": "134217728"      # 멀티파트 업로드 시작을 위한 128 MB 임계값
  driver:
    cores: 5
    memory: "20g"
    memoryOverhead: "6g"
    serviceAccount: spark-team-a
    securityContext:
      runAsUser: 185
    env:
      - name: JAVA_HOME
        value: "/opt/java/openjdk"
    nodeSelector:
      NodeGroupType: spark_benchmark_ebs
  executor:
    cores: 5
    memory: "20g"
    memoryOverhead: "6g"
    # 노드당 8개 실행기
    instances: 36 # 노드당 6개 pod; EKS 관리형 노드 그룹으로 6개 노드
    serviceAccount: spark-team-a
    securityContext:
      runAsUser: 185
    env:
      - name: JAVA_HOME
        value: "/opt/java/openjdk"
    nodeSelector:
      NodeGroupType: spark_benchmark_ebs
  restartPolicy:
    type: Never
```
