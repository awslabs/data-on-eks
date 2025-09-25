#---------------------------------------------------------------
# OpenSearch For DataHub metadata
#---------------------------------------------------------------
resource "aws_security_group" "es" {
  name        = "${var.prefix}-es-sg"
  description = "Allow inbound traffic to ElasticSearch from VPC CIDR"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "random_password" "master_password" {
  length      = 16
  special     = true
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

resource "aws_opensearch_domain" "es" {
  domain_name    = "${var.prefix}-es-domain"
  engine_version = "OpenSearch_2.19"
  cluster_config {
    dedicated_master_count = 0
    dedicated_master_type  = "c7g.large.search"
    instance_count         = length(var.vpc_private_subnets)
    instance_type          = "m7g.large.search"
    zone_awareness_enabled = true
    zone_awareness_config {
      availability_zone_count = min(length(var.vpc_private_subnets), 3)
    }
  }
  vpc_options {
    subnet_ids = var.vpc_private_subnets
    security_group_ids = [
      aws_security_group.es.id
    ]
  }
  encrypt_at_rest {
    enabled = true
  }
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
  node_to_node_encryption {
    enabled = true
  }
  ebs_options {
    ebs_enabled = true
    volume_size = "100"
    volume_type = "gp3"
  }
  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = "opensearch"
      master_user_password = random_password.master_password.result
    }
  }
}

# Creating the AWS Elasticsearch domain policy
resource "aws_opensearch_domain_policy" "main" {
  depends_on      = [aws_msk_cluster.msk]
  domain_name     = aws_opensearch_domain.es.domain_name
  access_policies = <<POLICIES
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "es:*",
            "Principal": "*",
            "Effect": "Allow",
            "Resource": "${aws_opensearch_domain.es.arn}/*"
        }
    ]
}
POLICIES
}

#---------------------------------------------------------------
# MSK For DataHub
#---------------------------------------------------------------
resource "aws_security_group" "msk" {
  name        = "${var.prefix}-msk-sg"
  description = "Allow inbound traffic to MSK from VPC CIDR"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_kms_key" "kms" {
  description = "${var.prefix}-msk-kms-key"
}

# Allow auto-create-topics
resource "aws_msk_configuration" "mskconf" {
  kafka_versions = ["3.9.x"]
  name           = "mskconf"

  server_properties = <<PROPERTIES
auto.create.topics.enable = true
delete.topic.enable = true
PROPERTIES
}

resource "aws_cloudwatch_log_group" "msklg" {
  name = "msk_broker_logs"
}

# Create cluster with smallest instance
resource "aws_msk_cluster" "msk" {
  cluster_name           = "${var.prefix}-msk"
  kafka_version          = "3.9.x"
  number_of_broker_nodes = length(var.vpc_private_subnets)

  broker_node_group_info {
    instance_type  = "kafka.m7g.large"
    client_subnets = var.vpc_private_subnets
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    security_groups = [aws_security_group.msk.id]
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
    }
    encryption_at_rest_kms_key_arn = aws_kms_key.kms.arn
  }

  configuration_info {
    arn      = aws_msk_configuration.mskconf.arn
    revision = aws_msk_configuration.mskconf.latest_revision
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msklg.name
      }
      firehose {
        enabled = false
      }
      s3 {
        enabled = false
      }
    }
  }
}

#---------------------------------------------------------------
# RDS MySQL for DataHub metadata
#---------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.prefix}-rds-sg"
  description = "Allow inbound traffic to MSK from VPC CIDR"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 0
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_db_subnet_group" "rds" {

  name        = "${var.prefix}_rds_subnet_gp"
  description = "${var.prefix} rds subnet groui"
  subnet_ids  = var.vpc_private_subnets

}

resource "random_password" "mysql_password" {
  length      = 16
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "aws_db_instance" "datahub_rds" {
  identifier = "${var.prefix}-mysql"

  engine         = "mysql"
  engine_version = "8.4.5"
  instance_class = "db.m7g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name = "db1"
  port    = 3306

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.rds.id
  vpc_security_group_ids = [aws_security_group.rds.id]

  username            = "admin"
  password            = random_password.mysql_password.result
  skip_final_snapshot = true
}
