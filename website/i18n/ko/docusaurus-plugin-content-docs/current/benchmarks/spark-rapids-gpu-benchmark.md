---
sidebar_position: 5
sidebar_label: Spark RAPIDS GPU 벤치마크
---

# Apache Spark와 NVIDIA RAPIDS GPU 가속 벤치마크

[Apache Spark](https://spark.apache.org/)는 대규모 분석 워크로드에 널리 사용되지만, 실행 효율성은 계산이 어떻게 수행되는지에 크게 의존합니다 - 기존 JVM 실행, CPU 벡터화, 또는 GPU 가속.

이 벤치마크는 Amazon EKS에서 세 가지 Spark 실행 전략에 걸친 **성능 및 비용 트레이드오프**를 평가합니다:

1. **네이티브 Spark** (기준 JVM 실행)
2. **Apache Gluten with Velox** (벡터화 CPU 실행)
3. **NVIDIA Spark RAPIDS** (GPU 가속)

하나의 접근 방식이 보편적으로 더 낫다고 가정하기보다, 이 연구의 목표는 더 실용적인 질문에 답하는 것입니다:

> *실제 분석 워크로드에서 성능, 안정성 및 총 소유 비용(TCO) 측면에서 다양한 Spark 실행 엔진은 어떻게 비교되나요?*

이에 답하기 위해 동일한 데이터셋과 비교 가능한 클러스터 구성을 사용하여 **TPC-DS 1TB 벤치마크(104개 쿼리, 3회 반복)**를 실행하고 다음을 측정했습니다:
- 엔드투엔드 실행 시간
- 쿼리 수준 성능 특성
- 워크로드 완료를 위한 인프라 비용
- 운영 안정성 및 메모리 동작

결과는 **단일 엔진이 모든 차원에서 지배하지 않음**을 보여줍니다:
- **Gluten/Velox**가 가장 빠른 전체 실행 시간 제공
- **RAPIDS GPU**가 특정 쿼리 패턴에서 뛰어나고 **가장 낮은 총 작업 비용** 달성
- **네이티브 Spark**는 비교를 위한 기준을 제공하지만 성능과 비용 효율성 모두에서 뒤처짐

[NVIDIA RAPIDS Accelerator for Apache Spark](https://nvidia.github.io/spark-rapids/)는 Spark SQL 및 DataFrame 연산을 NVIDIA GPU에 투명하게 오프로드하여 이 격차를 해소합니다. CPU 벡터화와 달리 GPU는 수천 개의 병렬 스레드를 동시에 처리하여 분석 쿼리에서 수 배의 속도 향상을 제공합니다. RAPIDS는 Spark의 실행 모델과 원활하게 통합되어 최소한의 코드 변경으로 [CUDA](https://developer.nvidia.com/cuda-toolkit) 에코시스템을 활용하여 최대 성능을 달성합니다.

이 가이드에서는:
- NVIDIA RAPIDS가 [Amazon EKS](https://aws.amazon.com/eks/)에서 Spark SQL을 어떻게 가속화하는지 이해합니다
- GPU 가속을 사용한 [TPC-DS](https://www.tpc.org/tpcds/) 1TB 벤치마크 결과를 검토합니다
- 프로덕션 워크로드에 필요한 구성, 배포 및 메모리 최적화를 배웁니다

:::tip TL;DR
<div className="quick-snapshot">
- **벤치마크 범위:** <span className="badge badge--info highlight-badge">TPC-DS 1TB</span>, GPU 가속을 사용하여 [Amazon EKS](https://aws.amazon.com/eks/)에서 3회 반복
- **툴체인:** <span className="badge badge--primary highlight-badge">Apache Spark 3.5.2</span> + <span className="badge badge--primary highlight-badge">NVIDIA RAPIDS v25.12.0</span> + <span className="badge badge--primary highlight-badge">CUDA 12.9</span>
- **하드웨어:** NVIDIA L4 GPU를 갖춘 <span className="badge badge--warning highlight-badge">4x g6.2xlarge 인스턴스</span>
- **총 실행 시간:** <span className="badge badge--success highlight-badge">약 2시간 실제 시간</span> (3회 반복 x 30분 + 오버헤드)
- **반복당 시간:** 104개 TPC-DS 쿼리에 <span className="badge badge--info highlight-badge">30.32분</span>
- **안정성:** 최적화된 메모리 구성으로 <span className="badge badge--success highlight-badge">OOM 킬 제로</span>
- **벤치마크 날짜:** <span className="badge badge--info highlight-badge">2026년 1월 12일</span> (타임스탬프: 1768275682804)
</div>

#### 비용 및 사양 비교 표

### 비용, 사양 및 성능 비교 표

| 엔진 | 인스턴스 유형 | 사용 노드 | 하드웨어 사양 (노드당) | 가속 | 실행 시간 (시간) | 온디맨드 비용 / 시간 | **총 작업 비용** | **네이티브 Spark 대비 성능** | **GPU 비용 이점** |
|------|---------------|-----------|--------------------------|--------------|-----------------|---------------------|--------------------|----------------------------------|------------------------|
| **네이티브 Spark** | c5d.12xlarge | 8 | 48 vCPU, 96 GiB RAM, NVMe SSD | 없음 (JVM) | 1.7 | $2.30 | **$31.28** | **1.0x (기준)** | **GPU가 약 80% 저렴 (약 5x)** |
| **Gluten / Velox** | c5d.12xlarge | 8 | 48 vCPU, 96 GiB RAM, NVMe SSD | Velox (CPU 벡터화) | 1.0 | $2.30 | **$18.40** | **1.7x 빠름** | **GPU가 약 66% 저렴 (약 2.9x)** |
| **RAPIDS GPU** | g6.2xlarge | 4 | 8 vCPU, 32 GiB RAM, 1x NVIDIA L4 (24 GB) | RAPIDS (GPU) | 1.6 | $0.98 | **$6.27** | **1.06x 빠름** | **기준** |

:::

## TPC-DS 1TB 벤치마크 결과: RAPIDS GPU 가속 성능 분석

### 요약

일반적인 가정은 "**CPU가 GPU보다 저렴하다**"입니다. 시간당 인스턴스 가격을 비교할 때는 사실일 수 있지만, 이 벤치마크는 왜 **총 소유 비용(TCO)**이 더 의미 있는 지표인지 보여줍니다.

Amazon EKS에서 네이티브 Spark, Gluten with Velox, NVIDIA RAPIDS를 사용하여 **TPC-DS 1TB 벤치마크(3회 반복)**를 실행했습니다. **Gluten/Velox가 가장 빠른 전체 실행 시간**을 달성했지만, **RAPIDS GPU는 달러당 더 높은 컴퓨팅 처리량으로 인해 상당히 낮은 총 비용으로 워크로드를 완료**했습니다.

쿼리 수준 성능은 엔진에 따라 다양했습니다:
- 일부 쿼리는 **CPU 벡터화(Velox)**에서 최고 성능
- 다른 쿼리는 **GPU 가속(RAPIDS)**에서 상당한 이점
- 단일 엔진이 모든 쿼리를 이기지 못함

이러한 결과는 가속 전략이 하드웨어 가격에 대한 가정이 아닌 **워크로드 특성과 비용 목표**에 따라 선택되어야 함을 강조합니다. 추가 튜닝을 통해 GPU 실행 시간을 더 줄여 여기에 표시된 것 이상으로 TCO를 개선할 수 있습니다.

상세한 쿼리별 결과와 구성 분석은 아래 섹션에서 제공됩니다.

**전체 벤치마크 구성 및 비교 분석이 이 가이드에서 제공됩니다**

### 벤치마크 인프라 구성

신뢰할 수 있는 GPU 가속 실행을 보장하기 위해 고정 메모리 풀과 GPU 메모리 관리를 포함한 RAPIDS 특정 요구 사항을 고려하여 메모리 할당을 신중하게 튜닝했습니다.

#### 테스트 환경 사양
| 구성 요소 | 구성 |
|-----------|--------------|
| **EKS 클러스터** | [Amazon EKS](https://aws.amazon.com/eks/) 1.34 |
| **GPU 인스턴스 유형** | g6.2xlarge (8 vCPU, 32GB RAM, NVIDIA L4 24GB GPU) |
| **GPU 노드** | 실행기 워크로드용 4개 노드 |
| **CPU 드라이버 노드** | c6i.2xlarge (8 vCPU, 16GB RAM) |
| **실행기 구성** | 4개 실행기 x 4 코어 x 16GB RAM + 12GB 오버헤드 각각 |
| **드라이버 구성** | 4 코어 x 8GB RAM + 2GB 오버헤드 |
| **데이터셋** | [TPC-DS](https://www.tpc.org/tpcds/) 1TB (Parquet 형식) |
| **스토리지** | AWS SDK v2를 사용하는 [Amazon S3](https://aws.amazon.com/s3/) |

#### 소프트웨어 스택 구성

| 구성 요소 | 버전 | 세부 사항 |
|-----------|---------|---------|
| **Apache Spark** | 3.5.2 | Hadoop 3.4와 안정 릴리스 |
| **NVIDIA RAPIDS** | v25.12.0 | Apache Spark용 RAPIDS Accelerator |
| **CUDA Toolkit** | 12.9 | NVIDIA CUDA 런타임 및 라이브러리 |
| **cuDF 라이브러리** | 번들됨 | GPU DataFrame 라이브러리 (RAPIDS에 포함) |
| **Java 런타임** | [OpenJDK](https://openjdk.org/) 17.0.17 | RAPIDS용 JVM 모듈 액세스가 있는 Ubuntu 빌드 |
| **Scala 버전** | 2.12.18 | Spark와 바이너리 호환성 |
| **컨테이너 이미지** | varabonthu/spark352-rapids25-tpcds4-cuda12-9:v1.1.0 | 사용자 정의 RAPIDS 활성화 Spark 이미지 |

#### 중요한 RAPIDS GPU 구성

```yaml
# NVIDIA RAPIDS 플러그인 활성화
spark.plugins: "com.nvidia.spark.SQLPlugin"
spark.rapids.sql.enabled: "true"

# GPU 메모리 관리 (OOM 방지에 중요)
spark.rapids.memory.pinnedPool.size: "2g"              # 호스트 RAM 고정 메모리 풀
spark.rapids.memory.gpu.pool: "ASYNC"                  # 비동기 GPU 메모리 할당
spark.rapids.memory.gpu.allocFraction: "0.8"           # GPU 메모리의 80%
spark.rapids.memory.gpu.maxAllocFraction: "0.9"        # 최대 90% GPU 메모리

# GPU 태스크 스케줄링
spark.task.resource.gpu.amount: "0.25"                 # 태스크당 1/4 GPU (4 코어)
spark.executor.resource.gpu.amount: "1"                # 실행기당 1 GPU
spark.rapids.sql.concurrentGpuTasks: "1"               # OOM 최소화를 위해 2에서 감소

# 최적화된 실행기 메모리 (OOM 킬 방지)
executor.memory: "16g"                                 # JVM 힙 메모리
executor.memoryOverhead: "12g"                         # 오프힙: 고정 + 네이티브 + 버퍼
# 총 Kubernetes 제한: 16g + 12g = 28Gi (32GB 노드에서 안전)

# RAPIDS 셔플 매니저
spark.shuffle.manager: "com.nvidia.spark.rapids.spark352.RapidsShuffleManager"
spark.rapids.shuffle.enabled: "true"
spark.rapids.shuffle.mode: "MULTITHREADED"
```

### 성능 결과: TPC-DS 1TB 쿼리 실행 시간

벤치마크는 3회 반복에 걸쳐 모든 104개 TPC-DS 쿼리를 실행하며, 각 쿼리에 대해 중앙값, 최소값 및 최대 실행 시간을 측정했습니다.

#### 전체 성능 지표

| 지표 | 값 |
|--------|-------|
| **총 실제 실행 시간** | 약 2시간 (Grafana 기준 19:30-21:30 UTC) |
| **총 반복 횟수** | 모든 104개 쿼리의 3회 완료 실행 |
| **반복당 실행 시간 (중앙값)** | 1,819.39초 (30.32분) |
| **반복당 실행 시간 (최소)** | 1,747.36초 (29.12분) |
| **반복당 실행 시간 (최대)** | 1,894.63초 (31.58분) |
| **평균 쿼리 시간 (쿼리당)** | 17.49초 |
| **실행된 총 쿼리** | 312 (104개 쿼리 x 3회 반복) |
| **스캔된 데이터** | 총 약 3TB (반복당 1TB) |
| **작업 가동 시간** | 1.6시간 (Spark 애플리케이션 가동 시간) |
| **실행기 재시작** | **0 (OOM 킬 제로!)** |
| **작업 완료율** | 100% (3,425개 Spark 작업 완료) |

#### 가장 빠른 상위 10개 쿼리 (GPU 최적화 연산)

| 순위 | TPC-DS 쿼리 | 중앙값 (초) | 최소 (초) | 최대 (초) | 특성 |
|------|-------------|-----------|---------|---------|-----------------|
| 1 | q41-v2.4 | 0.74 | 0.73 | 0.81 | 단순 집계 |
| 2 | q21-v2.4 | 1.07 | 1.04 | 1.07 | 필터 및 카운트 |
| 3 | q12-v2.4 | 1.25 | 1.25 | 1.45 | 날짜 범위 필터 |
| 4 | q92-v2.4 | 1.36 | 1.34 | 1.44 | 작은 테이블 조인 |
| 5 | q39b-v2.4 | 1.39 | 1.28 | 1.44 | 단순 조인 |
| 6 | q32-v2.4 | 1.51 | 1.50 | 1.72 | 카테고리 필터 |
| 7 | q20-v2.4 | 1.60 | 1.50 | 1.64 | 필터 및 합계 |
| 8 | q39a-v2.4 | 1.60 | 1.58 | 1.64 | q39b와 유사 |
| 9 | q52-v2.4 | 1.76 | 1.74 | 1.78 | 날짜 기반 그룹화 |
| 10 | q42-v2.4 | 1.79 | 1.72 | 1.83 | 단순 집계 |

#### 가장 느린 상위 10개 쿼리 (복잡한 분석 워크로드)

| 순위 | TPC-DS 쿼리 | 중앙값 (초) | 최소 (초) | 최대 (초) | 특성 |
|------|-------------|-----------|---------|---------|-----------------|
| 1 | q93-v2.4 | 118.21 | 116.19 | 119.76 | 복잡한 다중 조인 집계 |
| 2 | q24a-v2.4 | 114.98 | 114.08 | 116.36 | 대규모 데이터 스캔 |
| 3 | q67-v2.4 | 113.92 | 107.78 | 115.24 | 집계가 있는 와이드 조인 |
| 4 | q24b-v2.4 | 105.33 | 103.27 | 107.52 | 필터가 있는 q24a 변형 |
| 5 | q23b-v2.4 | 81.42 | 74.53 | 83.44 | 서브쿼리 중심 분석 |
| 6 | q28-v2.4 | 78.86 | 78.67 | 82.77 | 다차원 집계 |
| 7 | q50-v2.4 | 77.44 | 74.26 | 77.76 | 날짜 기반 필터링 |
| 8 | q23a-v2.4 | 75.84 | 69.76 | 76.03 | q23b 패턴과 유사 |
| 9 | q88-v2.4 | 69.31 | 65.80 | 72.39 | 윈도우 함수 |
| 10 | q78-v2.4 | 66.86 | 64.70 | 73.37 | 크로스 조인 연산 |

### 쿼리 성능 분포

| 실행 시간 범위 | 개수 | 전체 % |
|----------------------|-------|------------|
| < 5초 | 51 | 49.0% |
| 5-10초 | 16 | 15.4% |
| 10-20초 | 11 | 10.6% |
| 20-50초 | 15 | 14.4% |
| 50-100초 | 7 | 6.7% |
| > 100초 | 4 | 3.8% |

## 성능 비교: RAPIDS GPU vs Gluten/Velox vs 네이티브 Spark

### 비교된 벤치마크 구성

성능 트레이드오프를 이해하기 위해 세 가지 다른 Spark 실행 전략에서 동일한 TPC-DS 1TB 워크로드를 실행했습니다:

| 구성 | 타임스탬프 | 인스턴스 유형 | 코어/실행기 | 메모리/실행기 | 노드/실행기 | 가속 기술 |
|---------------|-----------|---------------|------------|-------------|-----------|------------------------|
| **RAPIDS GPU** | 1768275682804 | g6.2xlarge | 4 코어 | 16g + 12g 오버헤드 | 4/4 | NVIDIA L4 GPU (24GB GDDR6) |
| **Gluten/Velox** | 1758820934790 | c5d.12xlarge | 5 코어 | 20g + 6g 오버헤드 + 2gb 오프힙 | 8/23 | Velox 벡터화 엔진 |
| **네이티브 Spark** | 1758820220395 | c5d.12xlarge | 5 코어 | 20g + 6g 오버헤드 | 8/23 | 표준 Tungsten 실행 |


**성능 분석:**

- **Gluten/Velox**가 효율적인 벡터화 CPU 실행을 통해 최고의 전체 성능 달성
- **RAPIDS GPU**가 적당한 전체 속도 향상 (네이티브 대비 1.08x)을 보이지만 특정 쿼리 패턴에서 뛰어남
- **네이티브 Spark**는 기준 성능을 제공하지만 최신 CPU SIMD 명령어 최적화가 부족

### 가장 복잡한 상위 20개 쿼리: 비교 성능

| 쿼리 | 네이티브 Spark (초) | Gluten/Velox (초) | RAPIDS GPU (초) | 최고 | 최대 속도 향상 |
|-------|------------------|------------------|----------------|---------|-------------|
| q23b-v2.4 | 146.07 | 52.98 | 81.42 | Gluten | 2.76x |
| q23a-v2.4 | 113.96 | 47.05 | 75.84 | Gluten | 2.42x |
| q93-v2.4 | 80.04 | 14.47 | 118.21 | Gluten | 8.17x |
| q24a-v2.4 | 76.54 | 41.82 | 114.98 | Gluten | 2.75x |
| q67-v2.4 | 72.85 | 157.89 | 113.92 | 네이티브 | 2.17x |
| q24b-v2.4 | 71.59 | 39.40 | 105.33 | Gluten | 2.67x |
| q78-v2.4 | 63.85 | 27.42 | 66.86 | Gluten | 2.44x |
| q64-v2.4 | 62.07 | 27.35 | 49.84 | Gluten | 2.27x |
| q14a-v2.4 | 61.01 | 38.19 | 35.11 | **RAPIDS** | 1.74x |
| q28-v2.4 | 56.83 | 26.32 | 78.86 | Gluten | 3.00x |
| q14b-v2.4 | 54.54 | 37.35 | 28.22 | **RAPIDS** | 1.93x |
| q4-v2.4 | 52.98 | 25.98 | 58.11 | Gluten | 2.24x |
| q88-v2.4 | 50.65 | 20.72 | 69.31 | Gluten | 3.34x |
| q95-v2.4 | 50.01 | 47.49 | 25.40 | **RAPIDS** | 1.97x |
| q9-v2.4 | 48.08 | 19.23 | 21.98 | Gluten | 2.50x |
| q75-v2.4 | 40.65 | 16.10 | 43.16 | Gluten | 2.68x |
| q50-v2.4 | 38.45 | 9.95 | 77.44 | Gluten | 7.79x |
| q16-v2.4 | 31.31 | 19.57 | 33.22 | Gluten | 1.70x |
| q76-v2.4 | 25.89 | 14.60 | 38.93 | Gluten | 2.67x |
| q49-v2.4 | 25.89 | 6.69 | 24.63 | Gluten | 3.87x |

**범례:** RAPIDS GPU 최고 | Gluten/Velox 최고 | 네이티브 Spark 최고

### RAPIDS GPU가 뛰어난 곳

RAPIDS GPU는 다음 특성을 가진 쿼리에서 우수한 성능을 보여줍니다:
- 대규모 데이터 스캔이 있는 단순 집계
- 필터 중심 연산이 있는 프레디케이트 푸시다운
- 브로드캐스트 최적화가 있는 소형 테이블 조인

### 중앙값 쿼리 성능 비교 (TPC-DS 1TB)

| 쿼리 | RAPIDS 중앙값 (초) | Gluten 중앙값 (초) | 속도 향상 (x) | 더 빠른 엔진 |
|------|------------------|-------------------|-------------|---------------|
| q22-v2.4 | 1.99 | 22.74 | **11.46x** | **RAPIDS GPU** |
| q81-v2.4 | 4.82 | 14.10 | **2.93x** | **RAPIDS GPU** |
| q30-v2.4 | 4.82 | 13.20 | **2.74x** | **RAPIDS GPU** |
| q39b-v2.4 | 1.39 | 3.74 | **2.69x** | **RAPIDS GPU** |
| q69-v2.4 | 2.84 | 7.56 | **2.66x** | **RAPIDS GPU** |
| q10-v2.4 | 3.14 | 8.16 | **2.60x** | **RAPIDS GPU** |
| q39a-v2.4 | 1.60 | 4.09 | **2.56x** | **RAPIDS GPU** |
| q18-v2.4 | 5.08 | 11.57 | **2.28x** | **RAPIDS GPU** |
| q35-v2.4 | 4.71 | 10.47 | **2.22x** | **RAPIDS GPU** |
| q6-v2.4 | 1.84 | 3.79 | **2.06x** | **RAPIDS GPU** |

### Gluten/Velox가 뛰어난 곳

Gluten/Velox는 다음을 필요로 하는 쿼리에서 뛰어납니다:
- 복잡한 다단계 집계
- 대규모 셔플 연산이 있는 해시 조인
- SIMD 최적화가 있는 CPU 바운드 변환

| 쿼리 | Gluten (초) | RAPIDS (초) | 네이티브 (초) | 네이티브 대비 속도 향상 | RAPIDS 대비 속도 향상 |
|-------|------------|------------|------------|-------------------|-------------------|
| q93-v2.4 | 14.47 | 118.21 | 80.04 | 5.53x | **8.17x** |
| q49-v2.4 | 6.69 | 24.63 | 25.89 | 3.87x | 3.68x |
| q50-v2.4 | 9.95 | 77.44 | 38.45 | 3.87x | 7.79x |
| q59-v2.4 | 4.81 | 19.46 | 17.68 | 3.67x | 4.04x |
| q62-v2.4 | 2.77 | 8.94 | 9.43 | 3.41x | 3.23x |

### 기술적 인사이트: 왜 다른 엔진이 다른 쿼리에서 뛰어난가

**RAPIDS GPU 장점:**
- GPU 메모리 대역폭 (300 GB/s)이 스캔 중심 쿼리에 유리
- 대규모 병렬 처리 (7,424 CUDA 코어)가 단순 집계 가속
- GPU 네이티브 Parquet 디코딩이 CPU 역직렬화 오버헤드 제거
- 최적: 필터-스캔-집계 패턴, 소형 조인, 프레디케이트 푸시다운

**RAPIDS GPU 제한:**
- 복잡한 해시 조인이 PCIe 전송 오버헤드로 고통
- 셔플 중심 쿼리가 호스트-GPU 메모리 복사 지연으로 제한
- 일부 연산이 자동으로 CPU 실행으로 폴백
- 어려움: 다단계 셔플, 복잡한 서브쿼리 (예: q93, q50)

**Gluten/Velox 장점:**
- CPU SIMD 벡터화 (AVX-512)가 컬럼 연산 최적화
- 제로 카피 데이터 구조가 직렬화 오버헤드 최소화
- 적응형 실행이 복잡한 조인 전략 최적화
- 최적: 복잡한 조인, 다단계 집계, CPU 바운드 변환

## 결론: 올바른 가속 전략 선택

### 세 가지 실행 엔진에 걸친 성능 요약

Amazon EKS에서의 포괄적인 TPC-DS 1TB 벤치마크는 세 가지 다른 Spark 실행 전략을 비교했습니다:

| 구성 | 총 시간 | 네이티브 대비 속도 향상 | 승리한 쿼리 | 최적 사용 사례 |
|---------------|------------|-------------------|-------------|---------------|
| **네이티브 Spark** | 32.66분 | 기준 (1.0x) | 5 / 104 (4.9%) | 범용 워크로드 |
| **Gluten/Velox** | **19.36분** | **1.69x** | **57 / 104 (55.3%)** | CPU 집약적 분석 |
| **RAPIDS GPU** | 30.32분 | 1.08x | 41 / 104 (39.8%) | 스캔 중심 쿼리 |

### 주요 발견 사항

**1. Gluten/Velox가 최고의 전체 성능 제공**
- 표준 CPU 인스턴스를 사용하여 네이티브 Spark 대비 1.69x 속도 향상
- 복잡한 다단계 집계 및 해시 조인에서 뛰어남
- 최고의 가격 대비 성능 (GPU 프리미엄 불필요)
- 최소한의 운영 오버헤드로 프로덕션 준비

**2. RAPIDS GPU가 특정 쿼리 패턴에서 뛰어남**
- 개별 쿼리에서 최대 11.46x 속도 향상 (q22)
- 대규모 스캔이 있는 단순 집계에서 우수
- GPU 메모리 대역폭 (300 GB/s)이 필터 중심 연산에 유리
- PCIe 전송 오버헤드로 복잡한 셔플에서 어려움

**3. 네이티브 Spark 기준 성능**
- SIMD 벡터화 최적화 부족
- 최적화가 도움이 되지 않는 5개 쿼리에서만 승리
- 성능 요구 사항이 없는 범용 워크로드에 적합

### 프로덕션 권장 사항
**RAPIDS GPU 선택 시:**
- 워크로드가 스캔-집계 패턴에 의해 지배됨 (쿼리 프로파일링을 통해 확인)
- 80% GPU 인스턴스 프리미엄을 허용하는 예산
- 테스트에서 3-5x 개별 속도 향상을 보이는 쿼리
- 안정적인 메모리 구성 (16g + 12g 오버헤드) 검증됨

**Gluten/Velox 선택 시:**
- 다양한 분석 워크로드 실행 (TPC-DS, TPC-H, 임시 쿼리)
- 비용 최적화가 우선순위
- 다단계 집계가 있는 복잡한 쿼리가 지배적
- **대부분의 EKS Spark 배포에 권장**

**네이티브 Spark 선택 시:**
- 성능 SLA가 없는 범용 워크로드
- 운영 복잡성 최소화가 우선순위
- 기준 성능이 비즈니스 요구 사항 충족

### RAPIDS GPU 프로덕션 배포 체크리스트

RAPIDS GPU 배포 시 확인:

1. **메모리 구성**: `memoryOverhead >= 12GB` (2GB 고정 메모리 풀 포함)
2. **GPU 리소스**: NVIDIA 장치 플러그인이 `nvidia.com/gpu`를 Kubernetes에 노출
3. **모니터링**: Grafana 대시보드가 GPU 활용도 및 메모리 패턴 추적
4. **폴백 감지**: `spark.rapids.sql.explain=NOT_ON_GPU`가 CPU 폴백 식별
5. **인스턴스 선택**: g6.2xlarge가 28Gi 제한 제공 (16g 힙 + 12g 오버헤드)
6. **안정성**: `concurrentGpuTasks=1`로 OOM 킬 제로 검증됨

## 벤치마크 아티팩트 및 재현성

이 벤치마크를 재현하는 데 필요한 모든 아티팩트는 data-on-eks 리포지토리에서 사용할 수 있습니다:

### Docker 이미지

이 벤치마크에 사용된 전체 Dockerfile에는 Spark 3.5.2, RAPIDS 25.12.0, CUDA 12.9 및 TPC-DS 툴킷이 포함되어 있습니다:

**[Dockerfile-spark352-rapids25-tpcds4-cuda12-9](https://github.com/awslabs/data-on-eks/blob/main/data-stacks/spark-on-eks/benchmarks/spark-rapids-benchmarks/Dockerfile-spark352-rapids25-tpcds4-cuda12-9)**

이 Dockerfile은 다음을 보여줍니다:
- NVIDIA CUDA 12.9 베이스 이미지 구성
- RAPIDS Accelerator 플러그인 통합
- RAPIDS 호환성을 위한 Java 17 모듈 액세스 구성
- TPC-DS 데이터 생성 및 쿼리 실행 도구
- 최적화된 Spark 및 Hadoop 종속성 버전

### 벤치마크 결과

2026년 1월 12일 실행의 전체 벤치마크 결과 (타임스탬프: 1768275682804), 3회 반복에 걸쳐 모든 104개 TPC-DS 쿼리의 중앙값, 최소 및 최대 실행 시간 포함:

**TPC-DS v2.4 쿼리 결과 (주요 벤치마크):**
**[sparkrapids-benchmark-tpcds24-results.csv](https://github.com/awslabs/data-on-eks/blob/main/data-stacks/spark-on-eks/benchmarks/spark-rapids-benchmarks/results/sparkrapids-benchmark-tpcds24-results.csv)**

**TPC-DS v4.0 쿼리 결과 (비교 실행):**
**[sparkrapids-benchmark-tpcds40-results.csv](https://github.com/awslabs/data-on-eks/blob/main/data-stacks/spark-on-eks/benchmarks/spark-rapids-benchmarks/results/sparkrapids-benchmark-tpcds40-results.csv)**

**TPC-DS v2.4 vs v4.0 비교:**
**[sparkrapids-benchmark-tpcds24-vs-tpcds40-comparison.csv](https://github.com/awslabs/data-on-eks/blob/main/data-stacks/spark-on-eks/benchmarks/spark-rapids-benchmarks/results/sparkrapids-benchmark-tpcds24-vs-tpcds40-comparison.csv)**

각 CSV에는 다음이 포함됩니다:
- 쿼리 이름 (TPC-DS 쿼리)
- 중앙값 실행 시간 (초)
- 반복에 걸친 최소 실행 시간 (초)
- 반복에 걸친 최대 실행 시간 (초)

---
