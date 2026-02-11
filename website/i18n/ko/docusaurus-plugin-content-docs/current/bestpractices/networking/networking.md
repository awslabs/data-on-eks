---
sidebar_label: VPC 구성
---

# 데이터를 위한 네트워킹

## VPC 및 IP 고려 사항

### 기본 VPC CNI 구성
기본 VPC CNI 구성에서는 더 큰 노드가 더 많은 IP 주소를 소비합니다. 예를 들어 10개의 Pod를 실행하는 [`m5.8xlarge` 노드](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)는 총 60개의 IP를 보유합니다(`WARM_ENI_TARGET=1`을 충족하기 위해). 그러나 `m5.16xlarge` 노드는 100개의 IP를 보유합니다.

AWS VPC CNI는 Pod에 할당하기 위해 EKS 워커 노드에서 이 "웜 풀(warm pool)"의 IP 주소를 유지합니다. Pod에 더 많은 IP 주소가 필요하면 CNI는 EC2 API와 통신하여 노드에 주소를 할당해야 합니다.

### EKS 클러스터에서 많은 양의 IP 주소 사용을 계획하세요.

높은 변동(churn) 기간이나 대규모 확장 중에 이러한 EC2 API 호출은 속도 제한될 수 있으며, 이로 인해 Pod 프로비저닝이 지연되고 워크로드 실행이 지연됩니다. 또한 이 웜 풀을 최소화하도록 VPC CNI를 구성하면 노드에서 EC2 API 호출이 증가하고 속도 제한 위험이 높아질 수 있습니다.


### VPC 용량 제한을 피하기 위해 네트워크 주소 사용량(NAU) 모니터링

[네트워크 주소 사용량(NAU)](https://docs.aws.amazon.com/vpc/latest/userguide/network-address-usage.html)은 VPC의 총 크기를 추적하는 메트릭입니다. 각 VPC에는 기본 64,000 NAU 단위 제한이 있으며(256,000까지 증가 가능), 같은 리전의 피어링된 VPC는 128,000 NAU 단위(512,000까지 증가 가능)의 결합 제한을 공유합니다.

EKS의 데이터 워크로드의 경우 NAU 소비가 빠르게 증가할 수 있는 이유는 다음과 같습니다:

- **각 Pod IP 주소는 1 NAU 단위로 계산** - 수백 또는 수천 개의 익스큐터가 있는 대규모 Spark 작업은 상당한 NAU를 소비할 수 있습니다
- **웜 IP 풀이 사용량을 증폭** - VPC CNI의 웜 풀은 노드가 활성 Pod보다 더 많은 IP를 보유한다는 것을 의미하며, NAU 소비가 배가됩니다

수천 개의 Pod로 확장되는 데이터 플랫폼은 IP 주소가 아닌 사용 가능한 NAU 부족으로 인해 리소스 프로비저닝 실패를 일으킬 수 있습니다. 서브넷에 사용하지 않은 IP 주소가 많이 있더라도 각 IP가 VPC 전체 NAU 할당량에 포함되기 때문에 NAU 제한에 도달할 수 있습니다. CloudWatch 메트릭 `NetworkAddressUsage`를 통해 VPC의 NAU 사용량을 모니터링하고, 특히 대규모 배치 작업이나 스트리밍 워크로드를 실행할 때 용량을 적절히 계획하세요.

Pod IP로 인한 NAU 소비를 줄이려면 [VPC CNI 프리픽스 모드](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html)를 활성화하는 것을 고려하세요. 프리픽스 모드에서 CNI는 개별 IP 대신 /28 IPv4 프리픽스(16개 주소)를 ENI에 할당합니다. **각 프리픽스는 16개의 개별 단위가 아닌 1 NAU 단위로만 계산**되어 Pod IP에 대한 NAU 소비를 최대 16배까지 효과적으로 줄일 수 있습니다.

그러나 프리픽스 모드에는 연속된 /28 IP 주소 블록이 필요합니다. IP 할당이 분산된 조각화된 서브넷은 프리픽스 할당 실패를 일으킬 수 있습니다. 이를 방지하려면 EKS 클러스터 전용 새 서브넷을 생성하거나 [VPC 서브넷 CIDR 예약](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-cidr-reservation.html)을 사용하여 프리픽스를 위한 연속 공간을 예약하세요.

프리픽스 모드를 사용할 때 VPC CNI에서 `WARM_PREFIX_TARGET=1`을 구성하여 빠른 Pod 시작 시간을 유지하면서 사용하지 않는 IP 주소를 최소화하세요. 이 구성 옵션은:
- 즉각적인 Pod 할당을 위해 인스턴스의 네트워크 인터페이스에서 정의된 수의 프리픽스(/28 CIDR 블록)를 사용 가능하게 유지합니다
- 기존 프리픽스에서 단일 IP만 소비되더라도 전체 /28 프리픽스를 할당합니다
- 현재 ENI에 다른 프리픽스를 할당할 공간이 없으면 새 ENI를 생성합니다

자세한 VPC CNI 구성 가이드는 [Amazon VPC CNI 플러그인이 더 적은 IP 주소를 사용하도록 구성하는 방법](https://repost.aws/knowledge-center/eks-configure-cni-plugin-use-ip-address)과 아래의 [VPC CNI 튜닝](#tuning-the-vpc-cni) 섹션을 참조하세요.


### IP 공간이 제한된 경우 보조 CIDR 사용을 고려하세요.

여러 연결된 VPC 또는 사이트에 걸쳐 있는 네트워크로 작업하는 경우 라우팅 가능한 주소 공간이 제한될 수 있습니다.
예를 들어, VPC가 아래와 같이 작은 서브넷으로 제한될 수 있습니다. 이 VPC에서는 CNI 구성을 조정하지 않고는 `m5.16xlarge` 노드를 하나 이상 실행할 수 없습니다.

![Init VPC](init-vpc.png)

VPC 간에 라우팅할 수 없는 범위(예: RFC 6598 범위, `100.64.0.0/10`)에서 추가 VPC CIDR을 추가할 수 있습니다. 이 경우 `100.64.0.0/16`, `100.65.0.0/16`, `100.66.0.0/16`을 VPC에 추가한 다음(최대 CIDR 크기이므로) 해당 CIDR로 새 서브넷을 생성했습니다.
마지막으로 기존 EKS 클러스터 컨트롤 플레인은 그대로 두고 새 서브넷에 노드 그룹을 다시 생성했습니다.

![expanded VPC](expanded-vpc.png)

이 구성을 사용하면 연결된 VPC에서 EKS 클러스터 컨트롤 플레인과 계속 통신할 수 있지만 노드와 Pod는 워크로드와 웜 풀을 수용할 충분한 IP 주소를 갖습니다.


## VPC CNI 튜닝

### VPC CNI 및 EC2 속도 제한

EKS 워커 노드가 시작되면 처음에는 EC2 인스턴스가 통신하기 위한 단일 IP 주소가 있는 단일 ENI가 연결됩니다. VPC CNI가 시작되면 Kubernetes Pod에 할당할 수 있는 IP 주소의 웜 풀을 프로비저닝하려고 합니다([EKS 모범 사례 가이드에서 자세한 내용](https://aws.github.io/aws-eks-best-practices/networking/vpc-cni/#overview)).

VPC CNI는 해당 추가 IP와 ENI를 워커 노드에 할당하기 위해 AWS EC2 API 호출(예: `AssignPrivateIpV4Address` 및 `DescribeNetworkInterfaces`)을 수행해야 합니다. EKS 클러스터가 노드 또는 Pod 수를 확장할 때 이러한 EC2 API 호출이 급증할 수 있습니다. 이 호출 급증은 서비스 성능을 돕고 모든 Amazon EC2 고객의 공정한 사용을 보장하기 위해 EC2 API의 속도 제한에 직면할 수 있습니다. 이 속도 제한으로 인해 CNI가 더 많은 IP를 할당하려고 하는 동안 IP 주소 풀이 고갈될 수 있습니다.

이러한 실패는 VPC CNI가 IP 주소를 프로비저닝할 수 없어 컨테이너 네트워크 네임스페이스의 프로비저닝이 실패했음을 나타내는 아래와 같은 오류를 발생시킵니다.


```
Failed to create pod sandbox: rpc error: code = Unknown desc = failed to set up sandbox container "xxxxxxxxxxxxxxxxxxxxxx" network for pod "test-pod": networkPlugin cni failed to set up pod test-pod_default" network: add cmd: failed to assign an IP address to container
```

이 실패는 Pod 시작을 지연시키고 이 작업이 IP 주소가 할당될 때까지 재시도되므로 kubelet과 워커 노드에 부담을 줍니다. 이 지연을 방지하려면 필요한 EC2 API 호출 수를 줄이도록 CNI를 구성할 수 있습니다.


### 대규모 클러스터 또는 변동이 많은 클러스터에서 `WARM_IP_TARGET` 사용을 피하세요

`WARM_IP_TARGET`은 소규모 클러스터나 Pod 변동이 매우 낮은 클러스터에서 "낭비되는" IP를 제한하는 데 도움이 될 수 있습니다. 그러나 대규모 클러스터에서는 ipamd에 의한 IP 연결 및 분리 작업을 위한 EC2 API 호출 수가 증가하여 속도 제한의 위험과 영향이 증가할 수 있으므로 VPC CNI의 이 환경 변수를 신중하게 구성해야 합니다.
(`ipamd`는 IP Address Management Daemon의 약자이며, [VPC CNI의 핵심 구성 요소입니다](https://docs.aws.amazon.com/eks/latest/best-practices/networking.html#amazon-virtual-private-cloud-vpc-cni). 빠른 Pod 시작 시간을 위해 사용 가능한 IP의 웜 풀을 유지합니다.)

Pod 변동이 많은 클러스터의 경우, `MINIMUM_IP_TARGET`을 각 노드에서 실행할 예상 Pod 수보다 약간 높은 값으로 설정하는 것이 좋습니다. 이렇게 하면 CNI가 단일(또는 몇 번의) 호출로 모든 해당 IP 주소를 프로비저닝할 수 있습니다.

```hcl
  [...]

  # EKS Addons
  cluster_addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          MINIMUM_IP_TARGET        = "30"
        }
      })
    }
  }

  [...]
```
VPC CNI 변수 조정에 대한 자세한 정보는 [GitHub의 이 문서](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/eni-and-ip-target.md)를 참조하세요.

### `MAX_ENI` 및 `max-pods`를 사용하여 대형 인스턴스 유형에서 노드당 IP 수 제한

`16xlarge` 또는 `24xlarge`와 같은 더 큰 인스턴스 유형을 사용할 때 [ENI당 할당할 수 있는 IP 주소 수](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)가 상당히 많을 수 있습니다. 예를 들어, 기본 CNI 구성 `WARM_ENI_TARGET=1`을 가진 `c5.18xlarge` 인스턴스 유형은 몇 개의 Pod를 실행할 때 100개의 IP 주소(ENI당 50개의 IP * 2개의 ENI)를 보유하게 됩니다.

일부 워크로드의 경우 CPU, 메모리 또는 기타 리소스가 50개 이상의 IP가 필요하기 전에 해당 `c5.18xlarge`의 Pod 수를 제한합니다. 이 경우 해당 인스턴스에서 최대 30-40개의 Pod를 실행하고 싶을 수 있습니다.



```hcl
  [...]

  # EKS Addons
  cluster_addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          MAX_ENI           = "1"
        }
      })
    }
  }

  [...]
```


CNI에서 `MAX_ENI=1` 옵션을 설정하면 각 노드가 프로비저닝할 수 있는 IP 주소 수가 제한되지만, kubernetes가 노드에 스케줄링하려는 Pod 수는 제한되지 않습니다. 이로 인해 더 많은 IP 주소를 프로비저닝할 수 없는 노드에 Pod가 스케줄링되는 상황이 발생할 수 있습니다.

IP를 제한*하고* k8s가 너무 많은 Pod를 스케줄링하는 것을 중지하려면 다음을 수행해야 합니다:

1. CNI 구성 환경 변수를 업데이트하여 `MAX_ENI=1` 설정
2. 워커 노드의 kubelet에서 `--max-pods` 옵션 업데이트

--max-pods 옵션을 구성하려면 워커 노드의 userdata를 업데이트하여 [bootstrap.sh 스크립트의 --kubelet-extra-args를 통해](https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh) 이 옵션을 설정할 수 있습니다. 기본적으로 이 스크립트는 kubelet의 max-pods 값을 구성하며, `--use-max-pods false` 옵션은 자체 값을 제공할 때 이 동작을 비활성화합니다:

```hcl
  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.xlarge"]

      min_size     = 0
      max_size     = 5
      desired_size = 3

      pre_bootstrap_user_data = <<-EOT

      EOT

      bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=<your_value>'"

    }
```

한 가지 문제는 ENI당 IP 수가 인스턴스 유형에 따라 다르다는 것입니다([예를 들어 `m5d.2xlarge`는 ENI당 15개의 IP를 가질 수 있고, `m5d.4xlarge`는 ENI당 30개의 IP를 보유할 수 있습니다](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)). 이는 `max-pods` 값을 하드코딩하면 인스턴스 유형을 변경하거나 혼합 인스턴스 환경에서 문제가 발생할 수 있음을 의미합니다.

EKS 최적화 AMI 릴리스에는 [AWS 권장 max-pods 값을 계산하는 데 도움이 되는 스크립트가 포함](https://github.com/awslabs/amazon-eks-ami/blob/master/files/max-pods-calculator.sh)되어 있습니다. 혼합 인스턴스에 대해 이 계산을 자동화하려면 인스턴스 메타데이터에서 인스턴스 유형을 자동 검색하기 위해 `--instance-type-from-imds` 플래그를 사용하도록 인스턴스의 userdata도 업데이트해야 합니다.

```hcl
  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.xlarge"]

      min_size     = 0
      max_size     = 5
      desired_size = 3

      pre_bootstrap_user_data = <<-EOT
        /etc/eks/max-pod-calc.sh --instance-type-from-imds —cni-version 1.13.4 —cni-max-eni 1
      EOT

      bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=<your_value>'"

    }
```


#### Karpenter에서의 Maxpods

기본적으로 Karpenter가 프로비저닝한 노드는 [노드 인스턴스 유형에 기반한](https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt) 최대 Pod 수를 갖습니다. 위에서 언급한 대로 `--max-pods` 옵션을 구성하려면 `.spec.kubeletConfiguration` 내에서 `maxPods`를 지정하여 Provisioner 수준에서 정의할 수 있습니다. 이 값은 Karpenter Pod 스케줄링 중에 사용되며 kubelet 시작 시 `--max-pods`에 전달됩니다.

아래는 Provisioner 사양 예입니다:

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  providerRef:
    name: default
  requirements:
    - key: "karpenter.k8s.aws/instance-category"
      operator: In
      values: ["c", "m", "r"]
    - key: "karpenter.sh/capacity-type" # If not included, the webhook for the AWS cloud provider will default to on-demand
      operator: In
      values: ["spot", "on-demand"]

  # Karpenter provides the ability to specify a few additional Kubelet args.
  # These are all optional and provide support for additional customization and use cases.
  kubeletConfiguration:
    maxPods: 30
```


## 애플리케이션

### CoreDNS 스케일링
#### 기본 동작
Route 53 Resolver는 각 EC2 인스턴스에 대해 네트워크 인터페이스당 초당 1024 패킷 제한을 적용하며, 이 제한은 조정할 수 없습니다. EKS 클러스터에서 CoreDNS는 기본적으로 두 개의 레플리카로 실행되며, 각 레플리카는 별도의 EC2 인스턴스에 있습니다. DNS 트래픽이 CoreDNS 레플리카당 초당 1024 패킷을 초과하면 DNS 요청이 스로틀링되어 `unknownHostException` 오류가 발생합니다.

#### 해결책
기본 coreDNS의 확장성을 해결하려면 다음 두 가지 옵션 중 하나를 구현하는 것을 고려하세요:
  * [coreDNS 자동 스케일링 활성화](https://docs.aws.amazon.com/eks/latest/userguide/coredns-autoscaling.html).
  * [노드 로컬 캐시 구현](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/).


`CoreDNS`를 확장하는 동안 레플리카를 다른 노드에 분산시키는 것도 중요합니다. CoreDNS를 동일한 노드에 함께 배치하면 다시 ENI가 스로틀링되어 추가 레플리카가 효과가 없게 됩니다. `CoreDNS`를 노드 간에 분산시키려면 Pod에 노드 안티 어피니티 정책을 적용하세요:

```
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: k8s-app
          operator: In
          values:
          - kube-dns
      topologyKey: kubernetes.io/hostname
```

#### CoreDNS 모니터링
CoreDNS 메트릭을 지속적으로 모니터링하는 것이 좋습니다. 자세한 정보는 [EKS 네트워킹 모범 사례](https://docs.aws.amazon.com/eks/latest/best-practices/monitoring_eks_workloads_for_network_performance_issues.html#_monitoring_coredns_traffic_for_dns_throttling_issues)를 참조하세요.

### DNS 조회 및 ndots

[기본 DNS 구성을 가진 Kubernetes Pod](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)는 다음과 같은 `resolv.conf` 파일을 갖습니다:

```
nameserver 10.100.0.10
search namespace.svc.cluster.local svc.cluster.local cluster.local ec2.internal
options ndots:5
```

`search` 줄에 나열된 도메인 이름은 정규화된 도메인 이름(FQDN)이 아닌 DNS 이름에 추가됩니다. 예를 들어, Pod가 `servicename.namespace`를 사용하여 Kubernetes 서비스에 연결하려고 하면 DNS 이름이 전체 kubernetes 서비스 이름과 일치할 때까지 도메인이 순서대로 추가됩니다:

```
servicename.namespace.namespace.svc.cluster.local   <--- NXDOMAIN으로 실패
servicename.namespace.svc.cluster.local        <-- 성공
```

도메인이 정규화되었는지 여부는 resolv.conf의 `ndots` 옵션에 의해 결정됩니다. 이 옵션은 `search` 도메인을 건너뛰기 전에 도메인 이름에 있어야 하는 점의 수를 정의합니다. 이러한 추가 검색은 S3 및 RDS 엔드포인트와 같은 외부 리소스에 대한 연결에 지연 시간을 추가할 수 있습니다.

Kubernetes의 기본 `ndots` 설정은 5이며, 애플리케이션이 클러스터의 다른 Pod와 통신하지 않는 경우 `ndots`를 "2"와 같은 낮은 값으로 설정할 수 있습니다. 이것은 좋은 시작점입니다. 왜냐하면 애플리케이션이 동일한 네임스페이스와 클러스터 내의 다른 네임스페이스에서 서비스 검색을 수행할 수 있게 하면서도 `s3.us-east-2.amazonaws.com`과 같은 도메인이 FQDN으로 인식되도록(`search` 도메인 건너뛰기) 허용하기 때문입니다.

다음은 `ndots`를 "2"로 설정한 Kubernetes 문서의 예제 Pod 매니페스트입니다:

```yaml
apiVersion: v1
kind: Pod
metadata:
  namespace: default
  name: dns-example
spec:
  containers:
    - name: test
      image: nginx
  dnsConfig:
    options:
      - name: ndots
        value: "2"
```

:::info

Pod 배포에서 `ndots`를 "2"로 설정하는 것은 합리적인 시작점이지만, 모든 상황에서 보편적으로 작동하지 않으며 전체 클러스터에 적용해서는 안 됩니다. `ndots` 구성은 Pod 또는 Deployment 수준에서 구성해야 합니다. 클러스터 수준 CoreDNS 구성에서 이 설정을 줄이는 것은 권장되지 않습니다.

:::


### AZ 간 네트워크 최적화

일부 워크로드는 셔플 단계의 Spark 익스큐터와 같이 클러스터의 Pod 간에 데이터를 교환해야 할 수 있습니다.
Pod가 여러 가용 영역(AZ)에 분산되어 있는 경우, 이 셔플 작업은 특히 네트워크 I/O 측면에서 매우 비용이 많이 들 수 있습니다. 따라서 이러한 워크로드의 경우 익스큐터 또는 워커 Pod를 동일한 AZ에 배치하는 것이 좋습니다. 동일한 AZ에 워크로드를 배치하면 두 가지 주요 목적이 있습니다:

* AZ 간 트래픽 비용 절감
* 익스큐터/Pod 간 네트워크 지연 시간 감소

동일한 AZ에 Pod를 배치하려면 `podAffinity` 기반 스케줄링 제약 조건을 사용할 수 있습니다. 스케줄링 제약 조건 `preferredDuringSchedulingIgnoredDuringExecution`은 Pod 사양에서 적용할 수 있습니다. 예를 들어, Spark에서는 드라이버 및 익스큐터 Pod에 대해 사용자 정의 템플릿을 사용할 수 있습니다:

```yaml
spec:
  executor:
    affinity:
      podAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
              matchExpressions:
              - key: sparkoperator.k8s.io/app-name
                operator: In
                values:
                - <<spark-app-name>>
          topologyKey: topology.kubernetes.io/zone
          ...
```

Kubernetes Topology Aware Routing을 활용하여 Pod가 생성된 후 Kubernetes 서비스가 더 효율적인 방법으로 트래픽을 라우팅하도록 할 수도 있습니다: https://aws.amazon.com/blogs/containers/exploring-the-effect-of-topology-aware-hints-on-network-traffic-in-amazon-elastic-kubernetes-service/

:::info

모든 익스큐터가 단일 AZ에 위치하면 해당 AZ가 *단일 장애 지점*이 됩니다. 이는 네트워크 비용과 지연 시간을 낮추는 것과 AZ 장애가 워크로드를 중단시키는 이벤트 사이에서 고려해야 할 트레이드오프입니다.
워크로드가 용량이 제한된 인스턴스에서 실행 중인 경우 용량 부족 오류를 방지하기 위해 여러 AZ를 사용하는 것을 고려할 수 있습니다.

:::
