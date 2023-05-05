resource "aws_security_group" "es" {
  name = "${var.prefix}-es-sg"
  description = "Allow inbound traffic to ElasticSearch from VPC CIDR"
  vpc_id = var.vpc_id
  ingress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_iam_service_linked_role" "es" {
  aws_service_name = "opensearchservice.amazonaws.com"
}

resource "random_password" "master_password" {
  length  = 16
  special = true
}

resource "aws_opensearch_domain" "es" {
  domain_name = "${var.prefix}-es-domain"
  engine_version = "OpenSearch_1.1"
  cluster_config {
      dedicated_master_count = 0
      dedicated_master_type = "c6g.large.search"
      instance_count = length(var.vpc_private_subnets)
      instance_type = "m6g.large.search"
      zone_awareness_enabled = true
      zone_awareness_config {
        availability_zone_count = length(var.vpc_private_subnets)
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
      enforce_https = true      
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
    enabled = true
    internal_user_database_enabled = true
    master_user_options {
        master_user_name = "opensearch"
        master_user_password = random_password.master_password.result
    }
  }
}
 
# Creating the AWS Elasticsearch domain policy
 
resource "aws_opensearch_domain_policy" "main" {
  domain_name = aws_opensearch_domain.es.domain_name
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

resource "aws_security_group" "msk" {
  name = "${var.prefix}-msk-sg"
  description = "Allow inbound traffic to MSK from VPC CIDR"
  vpc_id = var.vpc_id
  ingress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_kms_key" "kms" {
  description =  "${var.prefix}-msk-kms-key"
}

resource "aws_msk_configuration" "mskconf" {
  kafka_versions = ["2.8.1"]
  name           = "mskconf"

  server_properties = <<PROPERTIES
auto.create.topics.enable = true
delete.topic.enable = true
PROPERTIES
}

resource "aws_cloudwatch_log_group" "msklg" {
  name = "msk_broker_logs"
}

resource "aws_msk_cluster" "msk" {
  cluster_name           = "${var.prefix}-msk"
  kafka_version          = "2.8.1"
  number_of_broker_nodes = length(var.vpc_private_subnets)

  broker_node_group_info {
    instance_type = "kafka.m5.large"
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
    arn = "${aws_msk_configuration.mskconf.arn}"
    revision = "${aws_msk_configuration.mskconf.latest_revision}"
  }
  
  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msklg.name
      }
      firehose {
        enabled         = false
      }
      s3 {
        enabled = false
      }
    }
  }
}

resource "aws_security_group" "rds" {
  name = "${var.prefix}-rds-sg"
  description = "Allow inbound traffic to MSK from VPC CIDR"
  vpc_id = var.vpc_id
  ingress {
      from_port = 0
      to_port = 3306
      protocol = "tcp"
      cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_db_subnet_group" "rds" {

  name        = "${var.prefix}_rds_subnet_gp"
  description = "${var.prefix} rds subnet groui"
  subnet_ids  = var.vpc_private_subnets

}

resource "random_password" "mysql_password" {
  length  = 16
  special = true
}

resource "aws_db_instance" "datahub_rds" {
  
  identifier = "${var.prefix}-mysql"

  # All available versions: http://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_MySQL.html#MySQL.Concepts.VersionMgmt
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.m6g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "db1"
  port     = 3306

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.rds.id
  vpc_security_group_ids = [aws_security_group.rds.id]

  username = "admin"
  password = random_password.mysql_password.result
}

resource "kubernetes_namespace" "datahub" {
  metadata {
    annotations = {
      name = local.datahub_namespace
    }

    labels = {
      mylabel = local.datahub_namespace
    }

    name = local.datahub_namespace
  }
}

resource "kubernetes_secret" "datahub_es_secret" {
  depends_on = [kubernetes_namespace.datahub, random_password.master_password]
  metadata {
    name = "elasticsearch-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    elasticsearch_password= random_password.master_password.result
  }

}

resource "kubernetes_secret" "datahub_rds_secret" {
  depends_on = [kubernetes_namespace.datahub, random_password.mysql_password]
  metadata {
    name = "mysql-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    mysql_root_password = random_password.mysql_password.result
  }

}
