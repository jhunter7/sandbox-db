# Provider Section
terraform {
  backend "s3" {
    bucket = "BUCKET_NAME"
    region = "us-west-2"
    key    = "tf-project"
  }
}

provider "aws" {
  region = "us-west-2"
}

# Variable Section
variable "sandbox_key_name" {} 

variable "app_env" {
  default = "production"
}

variable "app_id" {
  default = "db"
}

# Data Section
data "aws_db_instance" "primary" {
  db_instance_identifier = "dbsandbox-production"
}

data "aws_db_instance" "replica" {
  db_instance_identifier = "dbsandbox-production-replica-c"
}

data "aws_ami" "web" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["production-dbsandbox-web-*"]
  }
}

data "aws_instance" "web" {
  filter {
    name   = "tag:Name"
    values = ["production-dbsandbox-web-1"]
  }
}

data "aws_security_group" "solarwinds" {
  filter {
    name   = "group-name"
    values = ["production-solarwinds-dpm-agent"]
  }

}

data "aws_security_group" "influxdb" {
  filter {
    name   = "group-name"
    values = ["influxdb"]
  }
}

data "aws_security_group" "dbsandbox_production" {
  filter {
    name   = "group-name"
    values = ["db-production-APtRQgLYQZk"]
  }
}

data "aws_security_group" "production_telegraf" {
  filter {
    name   = "group-name"
    values = ["production-telegraf"]
  }
}

data "aws_security_group" "db_production_lb" {
  filter {
    name   = "group-name"
    values = ["db-production-lb"]
  }
}



# copy from db_production
resource "aws_security_group" "db_sandbox" {
  name        = "db-sandbox-${terraform.workspace}"
  description = "Security Group for sandbox instances"
  vpc_id      = data.aws_security_group.db_production.vpc_id
  ingress {
    description     = "HTTPS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [data.aws_security_group.production_telegraf.id, data.aws_security_group.db_production_lb.id]
  }
  tags = {
    "app:role"    = "sandbox"
    "app:cluster" = "production"
    "app:id"      = "db"
    "app:env"     = "production"
  }
}


resource "aws_security_group" "db_sandbox_postgresql" {
  name        = "db-sandbox-postgresql-${terraform.workspace}"
  description = "SG for sandbox db access"
  vpc_id      = data.aws_security_group.db_production.vpc_id

  ingress {
    description     = "Solarwinds DPM"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.solarwinds.id]
  }
  ingress {
    description     = "db Sandbox "
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db_sandbox.id]
  }
  ingress {
    description     = "Telegraf / InfluxDB"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.influxdb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "app:role"    = "sandbox"
    "app:cluster" = "production"
    "app:id"      = "db"
    "app:env"     = "production"
  }
}



resource "aws_db_instance" "sandbox" {
  identifier           = join("-", [var.app_env, var.app_id, "sandbox", terraform.workspace])
  instance_class       = data.aws_db_instance.primary.db_instance_class
  parameter_group_name = data.aws_db_instance.primary.db_parameter_groups[0]
  option_group_name    = data.aws_db_instance.primary.option_group_memberships[0]
  db_subnet_group_name = data.aws_db_instance.primary.db_subnet_group
  vpc_security_group_ids = setunion(data.aws_db_instance.primary.vpc_security_groups,
    [aws_security_group.db_sandbox_postgresql.id,
  aws_security_group.db_sandbox.id])
  iops                        = 10000
  publicly_accessible         = false
  multi_az                    = false
  deletion_protection         = false
  skip_final_snapshot         = true
  apply_immediately           = true
  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = false
  storage_encrypted           = true
  restore_to_point_in_time {
    source_db_instance_identifier = data.aws_db_instance.primary.db_instance_identifier
    use_latest_restorable_time    = true
  }
  tags = data.aws_db_instance.primary.tags
  timeouts {
    create = "24h"
  }
}

resource "aws_instance" "sandbox" {
  ami                         = data.aws_ami.web.image_id
  instance_type               = "r5.xlarge"
  associate_public_ip_address = data.aws_instance.web.associate_public_ip_address
  # key_name                    = data.aws_instance.web.key_name
  key_name                    = var.sandbox_key_name
  subnet_id                   = data.aws_instance.web.subnet_id
  vpc_security_group_ids = setunion(setsubtract(data.aws_instance.web.vpc_security_group_ids, [data.aws_security_group.db_production.id]),
  [aws_security_group.db_sandbox.id])
  tags = {
    Name          = join("-", [var.app_env, var.app_id, "sandbox", terraform.workspace])
    "app:env"     = var.app_env
    "app:id"      = var.app_id
    "app:cluster" = var.app_env
    "app:role"    = "sandbox"
  }

  user_data = <<-EOS
    #!/usr/bin/env bash

    sudo systemctl stop puma sidekiq sneakers que
    sudo systemctl disable puma sidekiq sneakers que
    sudo rm /opt/db/shared/.env.bak
    sudo -u deploy sed \
      -i.bak \
      -e 's/${data.aws_db_instance.primary.address}/${aws_db_instance.sandbox.address}/g' \
      -e 's/${data.aws_db_instance.replica.address}/${aws_db_instance.sandbox.address}/g' \
      -e '/REDIS/d' \
      -e '/MANDRILL/d' \
      /opt/db/shared/.env
  EOS
}

output "server_private_ip_address" {
  value = aws_instance.sandbox.private_ip
}

output "database_private_url" {
  value = aws_db_instance.sandbox.address
}
