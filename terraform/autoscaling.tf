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

  # IMDSv2. Hop limit 2 lets the container (one extra network hop) read the instance role for SQS.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
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
    aws_ssm_parameter.sqs_queue_url,
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
