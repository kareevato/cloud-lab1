resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/app"
  retention_in_days = 7
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# Після apply треба підтвердити підписку за посиланням у листі від AWS
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  alarm_name          = "${var.project}-no-healthy-hosts"
  alarm_description   = "ALB health check на /health не проходить"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project}-5xx-errors"
  alarm_description   = "Застосунок повертає 5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

locals {
  alb_dim = ["LoadBalancer", aws_lb.main.arn_suffix]
  asg_dim = ["AutoScalingGroupName", aws_autoscaling_group.app.name]
  rds_dim = ["DBInstanceIdentifier", aws_db_instance.postgres.identifier]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.project

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title  = "Instances (desired / in service)"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            concat(["AWS/AutoScaling", "GroupDesiredCapacity"], local.asg_dim),
            concat(["AWS/AutoScaling", "GroupInServiceInstances"], local.asg_dim),
          ]
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "CPU (%)"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            concat(["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app.name]),
          ]
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title   = "Requests per minute"
          region  = var.aws_region
          stat    = "Sum"
          period  = 60
          metrics = [concat(["AWS/ApplicationELB", "RequestCount"], local.alb_dim)]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Latency p95 (s)"
          region = var.aws_region
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb_dim, [{ stat = "p95" }]),
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "5xx"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.alb_dim),
            concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.alb_dim),
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 24, height = 6
        properties = {
          title   = "RDS CPU (%)"
          region  = var.aws_region
          stat    = "Average"
          period  = 60
          metrics = [concat(["AWS/RDS", "CPUUtilization"], local.rds_dim)]
        }
      },
    ]
  })
}
