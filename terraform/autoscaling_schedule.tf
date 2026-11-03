resource "aws_autoscaling_schedule" "day" {
  scheduled_action_name  = "${var.project}-day"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 2
  max_size               = 3
  desired_capacity       = 2
  recurrence             = "0 8 * * *"
  time_zone              = "Europe/Kyiv"
}

resource "aws_autoscaling_schedule" "night" {
  scheduled_action_name  = "${var.project}-night"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 1
  max_size               = 3
  desired_capacity       = 1
  recurrence             = "0 20 * * *"
  time_zone              = "Europe/Kyiv"
}
