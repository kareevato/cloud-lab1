variable "project" {
  type    = string
  default = "cloud-lab1"
}

variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "github_repositories" {
  type        = list(string)
  description = "Значення repo:<...> у claim 'sub' OIDC-токена GitHub"
  default = [
    "kareevato/cloud-lab1",
    "kareevato@180837586/cloud-lab1@1417455372",
  ]
}

variable "create_github_oidc_provider" {
  type        = bool
  description = "Створити OIDC-провайдер GitHub (false, якщо він уже є в акаунті)"
  default     = false
}

variable "admin_username" {
  type    = string
  default = "admin"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Пароль для POST /auth/login"
}

variable "alert_email" {
  type        = string
  description = "Email для алертів CloudWatch і бюджету"
}

variable "monthly_budget_usd" {
  type    = string
  default = "5"
}
