resource "aws_cloudwatch_metric_alarm" "at_max_capacity" {
  alarm_name          = "${var.project}-at-max-instances"
  alarm_description   = "Група тримає максимум екземплярів 2 хвилини: масштабування вперлося в стелю"
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.asg_max_size
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
