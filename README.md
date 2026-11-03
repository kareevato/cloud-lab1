# Cloud Lab 1

REST API для нотаток. Бекенд на Python (FastAPI) з PostgreSQL, запакований у Docker.

Гілка `main` — лабораторна 1, один EC2. Ця гілка додає лабораторну 2 і не замінює `main`.

**Публічна адреса:** http://cloud-lab1-alb-1413139306.eu-north-1.elb.amazonaws.com (діє лише під час демонстрації)

## Ендпоінти

- `GET /health` — перевірка стану сервера
- `GET /notes` — список нотаток
- `GET /notes/{id}` — нотатка за id
- `POST /auth/login` — JWT
- `POST /notes` — додати нотатку, лише з JWT
- `GET /docs` — Swagger UI

## Структура

```
app/ — застосунок
config/ — кеш у пам'яті
loadtest/ — сценарій k6
docs/ — опис лабораторної 2
Dockerfile
compose.yaml
terraform/ — інфраструктура в AWS
.github/workflows/ — автоматичний деплой
```

## Запуск локально

```
cp .env.example .env
docker compose up -d --build
```

Застосунок буде на `http://localhost:8000`.

## Розгортання в AWS

Інфраструктура описана в Terraform: мережа, ECR, база RDS у приватній підмережі, Auto Scaling Group і балансувальник.

```
cd terraform
terraform init
terraform apply
```

`terraform apply` на цій гілці замінює один EC2 лабораторної 1 на групу. Після захисту — `terraform destroy`.

## Лабораторна 2

Масштабування, навантажувальне тестування, моніторинг і кешування. Опис у папці docs:

- `docs/AUTOSCALING.md` — автомасштабування, параметри і пояснення
- `docs/LOADTEST.md` — сценарій k6 і результати
- `docs/ALERTS.md` — сповіщення на пошту
- `docs/CACHE.md` — кеш у пам'яті і порівняння
- `docs/SCHEDULE.md` — масштабування за розкладом і розрахунок економії

Тест запускається командою `k6 run -e BASE_URL=http://адреса -e ADMIN_PASSWORD='...' loadtest/test.js`.
