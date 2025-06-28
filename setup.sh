#!/bin/bash
set -e

# Load .env variables
if [ -f .env ]; then
    set -a
    . .env
    set +a
else
    echo "Error: .env file not found."
    exit 1
fi

: "${POSTGRES_DB:?POSTGRES_DB not set}"
: "${POSTGRES_USER:?POSTGRES_USER not set}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD not set}"

# Clean up any old containers (optional)
# docker compose down -v || true

# 1. Start DB (and odoo, but odoo will restart if DB not ready)
docker compose up -d --remove-orphans db

# 2. Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 60); do
    if docker compose exec db pg_isready -U "${POSTGRES_USER}" &>/dev/null; then
        echo "PostgreSQL is ready."
        break
    fi
    echo -n "."
    sleep 1
done

if ! docker compose exec db pg_isready -U "${POSTGRES_USER}" &>/dev/null; then
    echo "Error: PostgreSQL did not become ready in time."
    exit 1
fi

# 3. Ensure the DB exists (works even if already present)
echo "Ensuring PostgreSQL database '${POSTGRES_DB}' exists..."
docker compose exec db psql -U "${POSTGRES_USER}" -tc "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}';" | grep -q 1 || \
  docker compose exec db createdb -U "${POSTGRES_USER}" "${POSTGRES_DB}"

# 4. Initialise Odoo base module
docker compose run --rm odoo \
  odoo -c /etc/odoo/odoo.conf -d "${POSTGRES_DB}" -i base --stop-after-init

echo "Base module initialised. Now starting Odoo in normal mode..."
docker compose up -d --remove-orphans

