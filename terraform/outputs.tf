output "alb_public_url" {
  description = "Публічна адреса застосунку (через ALB)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "swagger_docs_url" {
  description = "Swagger UI"
  value       = "http://${aws_lb.main.dns_name}/docs"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "database_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "github_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "redis_private_ip" {
  value = aws_instance.redis.private_ip
}

output "ssm_session_command" {
  description = "Знайти інстанс застосунку і зайти без SSH"
  value       = "aws ec2 describe-instances --region ${var.aws_region} --filters Name=tag:Name,Values=${var.project}-app Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text"
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
