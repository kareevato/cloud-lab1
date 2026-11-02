resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "${local.param_prefix}/redis_password"
  type  = "SecureString"
  value = random_password.redis.result
}

resource "aws_iam_role" "redis" {
  name = "${var.project}-redis-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "redis_ssm_core" {
  role       = aws_iam_role.redis.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "redis_read_password" {
  name = "${var.project}-redis-password"
  role = aws_iam_role.redis.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.redis_password.arn
      },
      {
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com" } }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "redis" {
  name = "${var.project}-redis-profile"
  role = aws_iam_role.redis.name
}

# Окремий Redis замість ElastiCache: керований Redis не входить у Free Tier (~$12/міс).
# Публічна IP потрібна лише для вихідного docker pull і SSM. Вхід закритий security group.
resource "aws_instance" "redis" {
  ami                         = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_2.id
  vpc_security_group_ids      = [aws_security_group.redis_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.redis.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("${path.module}/user_data_redis.sh.tftpl", {
    region       = var.aws_region
    param_prefix = local.param_prefix
  })

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [
    aws_iam_role_policy.redis_read_password,
    aws_ssm_parameter.redis_password,
  ]

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
