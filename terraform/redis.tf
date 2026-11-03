resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "${local.param_prefix}/redis_password"
  type  = "SecureString"
  value = random_password.redis.result
}

# Окремий Redis замість ElastiCache (~$12/міс, поза бюджетом $5).
# Профіль застосунку вже читає /cloud-lab1/* і має SSM.
resource "aws_instance" "redis" {
  ami                         = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_2.id
  vpc_security_group_ids      = [aws_security_group.redis_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOT
#!/bin/bash
set -euxo pipefail
dnf install -y docker
systemctl enable --now docker
PASSWORD=$(aws ssm get-parameter --region ${var.aws_region} --with-decryption \
  --name ${local.param_prefix}/redis_password --query Parameter.Value --output text)
docker rm -f redis 2>/dev/null || true
docker run -d --name redis --restart always -p 6379:6379 \
  public.ecr.aws/docker/library/redis:7-alpine \
  redis-server --requirepass "$PASSWORD" --save "" --appendonly no
EOT

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_ssm_parameter.redis_password]

  tags = { Name = "${var.project}-redis" }
}

resource "aws_ssm_parameter" "redis_url" {
  name  = "${local.param_prefix}/redis_url"
  type  = "SecureString"
  value = "redis://:${random_password.redis.result}@${aws_instance.redis.private_ip}:6379/0"
}

resource "aws_ssm_parameter" "cache_enabled" {
  name  = "${local.param_prefix}/cache_enabled"
  type  = "String"
  value = "true"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "cache_ttl" {
  name  = "${local.param_prefix}/cache_ttl_seconds"
  type  = "String"
  value = "45"
}
