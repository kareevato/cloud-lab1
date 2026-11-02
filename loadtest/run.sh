#!/usr/bin/env bash
# Один запуск сценарію лабораторної 2. Потрібні BASE_URL і ADMIN_PASSWORD.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${BASE_URL:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
  echo "Потрібні змінні BASE_URL і ADMIN_PASSWORD" >&2
  echo "Приклад: BASE_URL=http://<alb> ADMIN_PASSWORD=... VUS=15 ./loadtest/run.sh" >&2
  exit 1
fi

export ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
export VUS="${VUS:-15}"
SUMMARY="$ROOT/loadtest/summary.json"

if command -v k6 >/dev/null 2>&1; then
  k6 run --summary-export "$SUMMARY" \
    -e BASE_URL="$BASE_URL" \
    -e ADMIN_USERNAME="$ADMIN_USERNAME" \
    -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    -e VUS="$VUS" \
    loadtest/notes.js
else
  docker run --rm -i \
    -e BASE_URL -e ADMIN_USERNAME -e ADMIN_PASSWORD -e VUS \
    -v "$ROOT:/work" -w /work \
    grafana/k6:0.54.0 run --summary-export /work/loadtest/summary.json \
    -e BASE_URL="$BASE_URL" \
    -e ADMIN_USERNAME="$ADMIN_USERNAME" \
    -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    -e VUS="$VUS" \
    loadtest/notes.js
fi

echo "Звіт: $SUMMARY"
