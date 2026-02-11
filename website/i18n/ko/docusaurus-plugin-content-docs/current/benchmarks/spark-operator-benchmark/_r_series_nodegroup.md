```
    spark_benchmark_ebs = {
      name        = "spark_benchmark_ebs"
      description = "x86 또는 ARM을 사용하는 EBS가 있는 Spark 벤치마크용 관리형 노드 그룹"
      # "100."으로 시작하는 보조 CIDR 프라이빗 서브넷만 필터링. 노드/노드 그룹이 프로비저닝될 서브넷 ID
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      # x86 인스턴스의 경우 ami_type= AL2023_x86_64_STANDARD로 변경
      ami_type = "AL2023_ARM_64_STANDARD" # arm64

      # 블루프린트를 배포할 때 노드 그룹은 0개 인스턴스로 생성됩니다.
      # min_size와 desired_size를 6개 인스턴스로 변경할 수 있습니다
      # 노드 그룹이 생성된 후에는 terrafrom을 통해 desired_size가 적용되지 않을 수 있으므로 AWS 콘솔에서 조정해야 합니다.
      min_size     = 0 # 벤치마크 실행을 위해 min과 desired를 6으로 변경
      max_size     = 8
      desired_size = 0 # 벤치마크 실행을 위해 min과 desired를 6으로 변경

      # 이 스토리지는 NVMe SSD 인스턴스가 아닌 경우 셔플로 사용됩니다. 예: r8g 인스턴스
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 300
            volume_type           = "gp3"
            iops                  = 3000
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # 원하는 인스턴스 유형을 변경하고 ami_type과 일치시키세요
      instance_types = ["r8g.12xlarge"] # 다양한 인스턴스 유형으로 벤치마크를 실행하려면 인스턴스 유형 변경

      labels = {
        NodeGroupType = "spark_benchmark_ebs"
      }

      tags = {
        Name          = "spark_benchmark_ebs"
        NodeGroupType = "spark_benchmark_ebs"
      }
    }
```
