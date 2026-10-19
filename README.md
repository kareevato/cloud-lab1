# Cloud Lab 1 — Notes REST API на AWS

REST API для нотаток (FastAPI + PostgreSQL) з JWT-автентифікацією, розгорнутий в AWS (`eu-north-1`) через Terraform з автодеплоєм з GitHub Actions.

- **Публічна адреса:** http://cloud-lab1-alb-1413139306.eu-north-1.elb.amazonaws.com
- **Swagger UI:** http://cloud-lab1-alb-1413139306.eu-north-1.elb.amazonaws.com/docs

## Архітектура

```
Internet → ALB :80 → EC2 :8000 (Docker) → RDS PostgreSQL :5432 (private subnets)
GitHub push → Actions (OIDC) → ECR :<commit-sha> → SSM → EC2
```

ECR — реєстр образів, RDS — керована база, секрети — у SSM Parameter Store, логи й алерти — CloudWatch + SNS, бюджет — AWS Budgets.

## Ендпоінти

| Метод | Шлях | Доступ |
|---|---|---|
| GET | `/health`, `/`, `/notes` | публічні |
| POST | `/auth/login` | повертає JWT |
| POST | `/notes` | лише з JWT, інакше 401 |

## Структура

```
app/                  FastAPI застосунок
Dockerfile, compose.yaml
.github/workflows/    CI/CD
terraform/            інфраструктура (network, security, database, compute, alb, cicd, monitoring, budget)
```

## Запуск

```bash
# локально
cp .env.example .env && docker compose up -d --build

# AWS
cd terraform && cp terraform.tfvars.example terraform.tfvars && terraform init && terraform apply

# видалення
terraform destroy
```
