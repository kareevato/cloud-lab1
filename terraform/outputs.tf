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

output "instance_id" {
  value = aws_instance.app.id
}

output "ssm_session_command" {
  description = "Доступ до сервера без SSH"
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.app.id}"
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
