resource "aws_sqs_queue" "notes" {
  name                       = "${var.project}-notes"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
}

resource "aws_ssm_parameter" "sqs_queue_url" {
  name  = "${local.param_prefix}/sqs_queue_url"
  type  = "String"
  value = aws_sqs_queue.notes.url
}

resource "aws_launch_template" "worker" {
  name          = "${var.project}-worker"
  image_id      = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.worker_sg.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/user_data_worker.sh.tftpl", {
    region       = var.aws_region
    repo_url     = aws_ecr_repository.app.repository_url
    param_prefix = local.param_prefix
    log_group    = aws_cloudwatch_log_group.app.name
  }))

  update_default_version = true

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project}-worker"
      Project = var.project
    }
  }
}

# Target tracking не вміє масштабувати групу до нуля, тому тут step/simple scaling.
resource "aws_autoscaling_group" "worker" {
  name                      = "${var.project}-worker-asg"
  min_size                  = 0
  max_size                  = 2
  desired_capacity          = 0
  vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  default_cooldown          = 120

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
  ]

  lifecycle {
    ignore_changes = [desired_capacity]
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  depends_on = [
    aws_iam_role_policy.ec2_app,
    aws_ssm_parameter.sqs_queue_url,
    aws_ssm_parameter.redis_url,
    aws_ssm_parameter.database_url,
    aws_ssm_parameter.image_tag,
  ]
}

resource "aws_autoscaling_policy" "worker_out" {
  name                   = "${var.project}-worker-out"
  autoscaling_group_name = aws_autoscaling_group.worker.name
  adjustment_type        = "ExactCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
  policy_type            = "SimpleScaling"
}

resource "aws_autoscaling_policy" "worker_in" {
  name                   = "${var.project}-worker-in"
  autoscaling_group_name = aws_autoscaling_group.worker.name
  adjustment_type        = "ExactCapacity"
  scaling_adjustment     = 0
  cooldown               = 180
  policy_type            = "SimpleScaling"
}

resource "aws_cloudwatch_metric_alarm" "queue_has_messages" {
  alarm_name          = "${var.project}-queue-has-messages"
  alarm_description   = "У черзі є повідомлення — підняти одного воркера"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.notes.name
  }

  alarm_actions = [aws_autoscaling_policy.worker_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "queue_empty" {
  alarm_name          = "${var.project}-queue-empty"
  alarm_description   = "Черга порожня кілька хвилин — прибрати воркера"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.notes.name
  }

  alarm_actions = [aws_autoscaling_policy.worker_in.arn]
}
