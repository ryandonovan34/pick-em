#!/usr/bin/env bash
# Usage: ./deploy.sh
# First run: creates the Fly.io app + Postgres, prompts for secrets, deploys.
# Subsequent runs: just deploys and runs migrations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="pickem-api"
PG_APP="${APP_NAME}-db"

# ── Prerequisites ─────────────────────────────────────────────────────────────
if ! command -v fly >/dev/null 2>&1; then
  echo "ERROR: flyctl not installed. Run: brew install flyctl"; exit 1
fi
if ! fly auth whoami >/dev/null 2>&1; then
  echo "ERROR: Not logged in. Run: fly auth login"; exit 1
fi

# ── App creation (first deploy only) ─────────────────────────────────────────
if ! fly status --app "$APP_NAME" >/dev/null 2>&1; then
  echo "==> Creating app: $APP_NAME"
  fly apps create "$APP_NAME"
fi

# ── Postgres (first deploy only) ─────────────────────────────────────────────
if ! fly status --app "$PG_APP" >/dev/null 2>&1; then
  echo "==> Creating Postgres cluster: $PG_APP (may take ~60 seconds)"
  fly postgres create \
    --name "$PG_APP" \
    --region iad \
    --initial-cluster-size 1 \
    --vm-size shared-cpu-1x \
    --volume-size 10
  echo "==> Attaching Postgres to $APP_NAME"
  fly postgres attach "$PG_APP" --app "$APP_NAME"
fi

# ── Secrets (only prompt for ones that aren't already set) ────────────────────
existing=$(fly secrets list --app "$APP_NAME" 2>/dev/null | awk 'NR>1 {print $1}' || true)

prompt_secret() {
  local key="$1" hint="$2"
  if ! grep -qx "$key" <<< "$existing"; then
    read -rsp "  $key ($hint): " val; echo
    fly secrets set "${key}=${val}" --app "$APP_NAME"
  fi
}

echo "==> Checking secrets..."
prompt_secret "SECRET_KEY"   "generate one with: openssl rand -hex 32"
prompt_secret "ODDS_API_KEY" "from the-odds-api.com — leave blank to skip live odds"

# ── Deploy ────────────────────────────────────────────────────────────────────
echo "==> Building and deploying..."
fly deploy --app "$APP_NAME"

# ── Migrations ────────────────────────────────────────────────────────────────
echo "==> Running database migrations..."
fly ssh console --app "$APP_NAME" -C "alembic upgrade head"

echo ""
echo "  App:      https://${APP_NAME}.fly.dev"
echo "  API docs: https://${APP_NAME}.fly.dev/docs"
