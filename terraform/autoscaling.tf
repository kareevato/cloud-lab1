resource "aws_autoscaling_group" "app" {
  name                    = "${var.project}-asg"
  min_size                = var.asg_min_size
  max_size                = var.asg_max_size
  desired_capacity        = var.asg_min_size
  vpc_zone_identifier     = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns       = [aws_lb_target_group.app.arn]
  health_check_type       = "ELB"
  default_cooldown        = 120
  default_instance_warmup = 60
  enabled_metrics         = ["GroupDesiredCapacity", "GroupInServiceInstances"]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  lifecycle {
    ignore_changes = [desired_capacity, min_size, max_size]
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project}-cpu"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = 50

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}
