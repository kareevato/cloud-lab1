#!/usr/bin/env bash
# Два однакові POST з одним Idempotency-Key мають повернути один і той самий запис.
set -euo pipefail

if [[ -z "${BASE_URL:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
  echo "Потрібні BASE_URL і ADMIN_PASSWORD" >&2
  exit 1
fi

USER_NAME="${ADMIN_USERNAME:-admin}"
TOKEN=$(curl -fsS -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${USER_NAME}\",\"password\":\"${ADMIN_PASSWORD}\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

KEY="lab2-$(date +%s)"
BODY='{"text":"idempotent note"}'

post() {
  curl -sS -D - -o /tmp/lab2-idem-body.json -X POST "$BASE_URL/notes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: $KEY" \
    -d "$BODY"
  echo
  cat /tmp/lab2-idem-body.json
  echo
}

echo "first request"
post
echo "second request (очікується Idempotent-Replayed: true і той самий id)"
post
