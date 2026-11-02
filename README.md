# Cloud Lab 2 — масштабування, моніторинг і кеш

Гілка `main` лишається лабораторною 1 (один EC2). Ця гілка додає лабораторну 2 в той самий Terraform-проєкт.

REST API для нотаток (FastAPI + PostgreSQL) з JWT і Redis cache-aside. В AWS (`eu-north-1`): ALB, Auto Scaling Group (1–3), окремий Redis, RDS у приватних підмережах. CI/CD — GitHub Actions через OIDC.

`terraform apply` на цій гілці **замінює** один EC2 лабораторної 1 на групу. Це свідомий крок, не побічний ефект. Після захисту — `terraform destroy`: Redis і додаткові екземпляри виходять за Free Tier.

- **Публічна адреса:** http://cloud-lab1-alb-1413139306.eu-north-1.elb.amazonaws.com
- **Swagger UI:** http://cloud-lab1-alb-1413139306.eu-north-1.elb.amazonaws.com/docs

## Архітектура

```
Internet → ALB :80 → ASG (1–3 × EC2 :8000) → RDS PostgreSQL :5432 (private)
                              ↘ Redis :6379 (окремий EC2, лише з SG застосунку)
GitHub push → Actions (OIDC) → ECR :<commit-sha> → SSM → усі інстанси групи
```

ECR — реєстр образів, RDS — керована база, секрети — у SSM Parameter Store, логи, панель і алерти — CloudWatch + SNS, бюджет — AWS Budgets.

Документи лабораторної 2:

- `docs/AUTOSCALING.md` — політика, warmup/cooldown, панель
- `docs/LOADTEST.md` — сценарій k6 і куди вписати результати
- `docs/ALERTS.md` — лист при максимумі екземплярів
- `docs/CACHE.md` — cache-aside і порівняння з вимкненим кешем
- `docs/SCHEDULE.md` — бонус: удень мінімум 2 екземпляри, уночі 1

## Ендпоінти

| Метод | Шлях | Доступ |
|---|---|---|
| GET | `/health`, `/`, `/notes`, `/notes/{id}`, `/authors/{name}`, `/cache/stats` | публічні |
| POST | `/auth/login` | повертає JWT |
| POST | `/notes` | лише з JWT, інакше 401 |

## Структура

```
app/                  FastAPI застосунок
Dockerfile, compose.yaml
.github/workflows/    CI/CD
terraform/            інфраструктура (network, security, database, compute, autoscaling, cache, alb, cicd, monitoring, budget)
loadtest/             сценарій k6
docs/                 опис політики, тестів, алертів і кешу
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
