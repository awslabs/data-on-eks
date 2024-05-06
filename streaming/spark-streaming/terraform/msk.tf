resource "aws_security_group" "msk_security_group" {
  name        = "msk-security-group"
  description = "Security group for MSK cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, element(var.secondary_cidr_blocks, 0)]
  }
  ingress {
    from_port   = 9198
    to_port     = 9198
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, element(var.secondary_cidr_blocks, 0)]
  }
  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, element(var.secondary_cidr_blocks, 0)]
  }
  ingress {
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, element(var.secondary_cidr_blocks, 0)]
  }
  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, element(var.secondary_cidr_blocks, 0)]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security is not enable here only for demo purposes, you should enable auth mechanisms
resource "aws_msk_cluster" "kafka_test_demo" {
  cluster_name           = "kafka-demo-spark"
  kafka_version          = "2.7.1"
  number_of_broker_nodes = 2

  broker_node_group_info {
    instance_type  = "kafka.m5.large"
    client_subnets = [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    connectivity_info {
      public_access {
        type = "DISABLED"
      }
    }
    security_groups = [aws_security_group.msk_security_group.id]
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
    }
  }

  client_authentication {
    sasl {
      iam = false
    }

    unauthenticated = true
  }
  #Lyfecycle to ignore
  lifecycle {
    ignore_changes = [
      client_authentication[0].tls
    ]
  }
}
