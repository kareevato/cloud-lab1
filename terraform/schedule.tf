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
