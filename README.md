# Cloud Lab 1 — Notes REST API на AWS

REST API для нотаток (FastAPI + PostgreSQL) з JWT-автентифікацією, розгорнутий в AWS (`eu-north-1`) через Terraform з автоматичним деплоєм з GitHub Actions.

**Публічна адреса:** http://cloud-lab1-alb-1413139306.eu-north-1.elb.amazonaws.com
**Swagger UI:** http://cloud-lab1-alb-1413139306.eu-north-1.elb.amazonaws.com/docs

## Ендпоінти

| Метод | Шлях | Доступ |
|---|---|---|
| GET | `/health` | публічний (health check ALB) |
| GET | `/` | публічний, повертає версію (хеш коміту) |
| POST | `/auth/login` | публічний, повертає JWT |
| GET | `/notes` | публічний |
| POST | `/notes` | тільки з `Authorization: Bearer <JWT>`, інакше 401 |

## Архітектура

```
Internet ──► ALB :80 (public subnets, 2 AZ) ──► EC2 :8000 (Docker, лише від SG ALB)
                                                   │
                                                   ▼
                                       RDS PostgreSQL :5432 (private subnets, лише від SG застосунку)

GitHub push ─► Actions (OIDC → IAM role) ─► ECR :<commit-sha> ─► SSM Run Command ─► EC2 перезапускає контейнер
Логи контейнера ─► CloudWatch Logs; метрики ─► дашборд; алерти ─► SNS ─► email
```

- **Реєстр:** Amazon ECR (`cloud-lab1-app`), скан при push, зберігаються 10 останніх образів.
- **База:** RDS PostgreSQL 15 `db.t4g.micro`, `publicly_accessible = false`, приватні підмережі.
- **Обчислення:** EC2 `t3.micro` (Amazon Linux 2023) з Docker. SSH закритий, доступ — через SSM Session Manager.
- **Секрети:** пароль бази та JWT-ключ генерує Terraform (`random_password`), вони зберігаються як SecureString в SSM Parameter Store. Інстанс читає їх через IAM-роль під час деплою і передає контейнеру як змінні середовища. У git секретів немає.
- **CI/CD:** `.github/workflows/deploy.yml` — OIDC, без access keys.
- **Моніторинг:** log group `/cloud-lab1/app`, дашборд `cloud-lab1` (запити, 5xx, латентність, CPU/пам'ять EC2 та RDS), алерти «немає здорових інстансів» і «5xx > 5 за 5 хв» на email.
- **Бюджет:** AWS Budgets з листами на email при 80% фактичних і 100% прогнозованих витрат.

## Структура

```
.
├── app/                    # FastAPI застосунок
│   ├── main.py
│   ├── database.py
│   └── requirements.txt
├── Dockerfile
├── compose.yaml            # локально: застосунок + PostgreSQL з volume
├── .env.example
├── .github/workflows/deploy.yml
└── terraform/
    ├── main.tf             # провайдери
    ├── variables.tf
    ├── network.tf          # VPC, публічні/приватні підмережі
    ├── security.tf         # security groups
    ├── database.tf         # RDS + SSM-секрети
    ├── ecr.tf
    ├── compute.tf          # EC2, IAM-роль інстансу
    ├── user_data.sh.tftpl  # встановлення Docker і скрипт деплою
    ├── alb.tf
    ├── cicd.tf             # IAM-роль для GitHub OIDC
    ├── monitoring.tf       # CloudWatch, SNS
    ├── budget.tf
    ├── outputs.tf
    └── terraform.tfvars.example
```

## Локальний запуск

```bash
cp .env.example .env   # заповнити значення
docker compose up -d --build
curl http://localhost:8000/health
```

Дані бази зберігаються у volume `postgres_data` і переживають `docker compose down`.

## Розгортання в AWS

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # admin_password, alert_email
terraform init
terraform apply
```

Після `apply` треба підтвердити підписку SNS за посиланням у листі. Потім push у `main` збирає образ, публікує його в ECR з тегом `<commit-sha>` і оновлює контейнер на EC2.

Відкат на попередню версію: запустити на інстансі `/usr/local/bin/deploy-app.sh <старий-sha>` (через `aws ssm send-command` або Session Manager) або зробити `git revert` і push.

Видалення всіх ресурсів: `terraform destroy`.
