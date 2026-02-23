다음 입력값으로 *taxi-trip-execute.sh* 스크립트를 실행합니다. 앞서 생성한 *S3_BUCKET* 변수를 사용합니다. 또한 YOUR_REGION_HERE를 원하는 리전으로 변경해야 합니다. 예: *us-west-2*

이 스크립트는 예제 택시 여행 데이터를 다운로드하고 크기를 늘리기 위해 복제본을 만듭니다. 이 작업은 시간이 걸리며 비교적 빠른 인터넷 연결이 필요합니다.

```bash
cd ${DOEKS_HOME}/analytics/scripts/
chmod +x taxi-trip-execute.sh
./taxi-trip-execute.sh ${S3_BUCKET} YOUR_REGION_HERE
```

블루프린트 디렉토리로 돌아가서 예제를 계속할 수 있습니다.
```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
```
