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

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 3

  validation {
    condition     = var.asg_max_size >= 2 && var.asg_max_size <= 4
    error_message = "Максимум екземплярів має бути від 2 до 4."
  }
}

