locals {
  lb_dim = aws_lb.main.arn_suffix
  asg    = aws_autoscaling_group.app.name
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.project

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Кількість екземплярів"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", local.asg],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", local.asg],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "CPU сервісу, %"
          region  = var.aws_region
          view    = "timeSeries"
          period  = 60
          stat    = "Average"
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Запити за хвилину"
          region  = var.aws_region
          view    = "timeSeries"
          period  = 60
          stat    = "Sum"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.lb_dim]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Затримка p95, с"
          region  = var.aws_region
          view    = "timeSeries"
          period  = 60
          stat    = "p95"
          metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb_dim]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Помилки 5xx"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.lb_dim],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.lb_dim],
          ]
        }
      },
    ]
  })
}
