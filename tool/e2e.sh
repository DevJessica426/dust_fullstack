#!/usr/bin/env bash
# Runs the official RealWorld front-end E2E suite (Playwright) against the
# Dart app: builds the web app, starts the server on its own port and
# database, seeds the demo users the suite expects, runs, and stops.
#
#   tool/e2e.sh                          # everything
#   tool/e2e.sh specs/auth.spec.ts       # one file (paths relative to e2e/)
#
# Needs: Dart, Node, PostgreSQL. The database named by E2E_DATABASE_URL is
# wiped at the start of every run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${E2E_PORT:-8090}"
DATABASE_URL="${E2E_DATABASE_URL:-postgres://conduit:conduit@localhost:5432/conduit_e2e?sslmode=disable}"
LOG="$ROOT/e2e/server.log"

cd "$ROOT"

if [ "${SKIP_WEB_BUILD:-}" != "1" ]; then
  tool/build_web.sh
fi

echo "resetting $DATABASE_URL"
psql "${DATABASE_URL%%\?*}" -qc 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' >/dev/null

DATABASE_URL="$DATABASE_URL" PORT="$PORT" \
  JWT_SECRET="e2e-secret-e2e-secret-e2e-secret-e2e" \
  WEB_ROOT="$ROOT/packages/conduit_web/build/web" \
  dart run packages/conduit_server/bin/server.dart >"$LOG" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT

for _ in $(seq 1 90); do
  curl -sf "http://localhost:$PORT/healthz" >/dev/null && break
  sleep 1
done
curl -sf "http://localhost:$PORT/healthz" >/dev/null || { cat "$LOG"; exit 1; }

dart run packages/conduit_server/bin/seed.dart "http://localhost:$PORT/api"

cd "$ROOT/e2e"
[ -d node_modules/@playwright/test ] || npm install --no-audit --no-fund
BASE_URL="http://localhost:$PORT" \
  API_BASE="http://localhost:$PORT/api" \
  TEST_MODE=spa \
  npx playwright test "$@"
