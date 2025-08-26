#!/bin/bash
set -euo pipefail

echo "Verifying Docker and Compose..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found in PATH"; exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "Error: Docker Compose plugin not installed (try installing docker-compose-plugin)"; exit 1
fi


# Load .env variables
if [ -f .env ]; then
  set -a; . .env; set +a
else
  echo "Error: .env file not found."; exit 1
fi

: "${POSTGRES_DB:?POSTGRES_DB not set}"
: "${POSTGRES_USER:?POSTGRES_USER not set}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD not set}"

# 1) Start DB
docker compose up -d --remove-orphans db

# 2) Wait for PostgreSQL
echo "Waiting for PostgreSQL to be ready..."
for i in {1..60}; do
  if docker compose exec -T db pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1; then
    echo "PostgreSQL is ready."; break
  fi
  printf "."; sleep 1
done
if ! docker compose exec -T db pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1; then
  echo -e "\nError: PostgreSQL did not become ready in time."; exit 1
fi

# 3) Ensure DB exists (no-op if already present)
echo "Ensuring database '${POSTGRES_DB}' exists..."
docker compose exec -T db psql -U "${POSTGRES_USER}" -d postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}';" >/dev/null || true

# 4) Initialise Odoo base module
docker compose run --rm odoo \
  odoo -c /etc/odoo/odoo.conf -d "${POSTGRES_DB}" -i base --stop-after-init

echo "Base module initialised. Starting Odoo normally..."
docker compose up -d  --watch --remove-orphans


