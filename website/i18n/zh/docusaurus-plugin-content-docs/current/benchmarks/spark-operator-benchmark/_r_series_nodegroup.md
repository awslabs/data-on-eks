```
    spark_benchmark_ebs = {
      name        = "spark_benchmark_ebs"
      description = "Managed node group for Spark Benchmarks with EBS using x86 or ARM"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      # Change ami_type= AL2023_x86_64_STANDARD for x86 instances
      ami_type = "AL2023_ARM_64_STANDARD" # arm64

      # Node group will be created with zero instances when you deploy the blueprint.
      # You can change the min_size and desired_size to 6 instances
      # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
      min_size     = 0 # Change min and desired to 6 for running benchmarks
      max_size     = 8
      desired_size = 0 # Change min and desired to 6 for running benchmarks

      # This storage is used as a shuffle for non NVMe SSD instances. e.g., r8g instances
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

      # Change the instance type as you desire and match with ami_type
      instance_types = ["r8g.12xlarge"] # Change Instance type to run the benchmark with various instance types

      labels = {
        NodeGroupType = "spark_benchmark_ebs"
      }

      tags = {
        Name          = "spark_benchmark_ebs"
        NodeGroupType = "spark_benchmark_ebs"
      }
    }
```
