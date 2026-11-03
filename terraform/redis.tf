resource "aws_instance" "redis" {
  ami                         = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_2.id
  vpc_security_group_ids      = [aws_security_group.redis_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  user_data                   = "#!/bin/bash\ndnf install -y docker\nsystemctl enable --now docker\ndocker run -d --name redis --restart always -p 6379:6379 public.ecr.aws/docker/library/redis:7-alpine\n"
  tags                        = { Name = "${var.project}-redis" }
}

resource "aws_ssm_parameter" "redis_url" {
  name  = "${local.param_prefix}/redis_url"
  type  = "String"
  value = "redis://${aws_instance.redis.private_ip}:6379/0"
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
