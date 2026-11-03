resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM Agent: Run Command (деплой з CI) і Session Manager (замість SSH)
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cw_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "ec2_app" {
  name = "${var.project}-ec2-app"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "ReadAppSecrets"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter${local.param_prefix}/*"
      },
      {
        Sid       = "DecryptSecureString"
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com" } }
      },
      {
        Sid      = "WriteAppLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_ssm_parameter" "image_tag" {
  name  = "${local.param_prefix}/image_tag"
  type  = "String"
  value = "latest"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_launch_template" "app" {
  name          = "${var.project}-app"
  image_id      = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    region       = var.aws_region
    repo_url     = aws_ecr_repository.app.repository_url
    param_prefix = local.param_prefix
    log_group    = aws_cloudwatch_log_group.app.name
  }))

  update_default_version = true

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project}-app"
      Project = var.project
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project}-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_min_size
  vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  # Класичний cooldown для simple scaling. Target tracking нижче використовує warmup.
  default_cooldown        = 180
  default_instance_warmup = 120

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupTotalInstances",
  ]

  # Розклад і target tracking змінюють ці значення поза Terraform.
  lifecycle {
    ignore_changes = [desired_capacity, min_size]
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  depends_on = [
    aws_iam_role_policy.ec2_app,
    aws_iam_role_policy_attachment.ec2_ssm_core,
    aws_ssm_parameter.database_url,
    aws_ssm_parameter.jwt_secret,
    aws_ssm_parameter.admin_username,
    aws_ssm_parameter.admin_password,
    aws_ssm_parameter.redis_url,
    aws_ssm_parameter.cache_enabled,
    aws_ssm_parameter.cache_ttl,
    aws_ssm_parameter.image_tag,
  ]
}

# Ціль — запити на інстанс, не CPU: процес більшість часу чекає на Postgres.
resource "aws_autoscaling_policy" "requests" {
  name                      = "${var.project}-requests-per-target"
  autoscaling_group_name    = aws_autoscaling_group.app.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 120

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = var.requests_per_target_per_minute
  }
}

# Удень тримаємо щонайменше 2 інстанси, вночі — 1. Час — Europe/Kyiv.
resource "aws_autoscaling_schedule" "day" {
  scheduled_action_name  = "${var.project}-day"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 2
  max_size               = var.asg_max_size
  desired_capacity       = 2
  recurrence             = "0 8 * * *"
  time_zone              = "Europe/Kyiv"
}

resource "aws_autoscaling_schedule" "night" {
  scheduled_action_name  = "${var.project}-night"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 1
  max_size               = var.asg_max_size
  desired_capacity       = 1
  recurrence             = "0 23 * * *"
  time_zone              = "Europe/Kyiv"
}

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
echo "Redis is up"
EOT

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
