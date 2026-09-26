#!/usr/bin/env bash
# Runs the official RealWorld Hurl suite against a running Conduit server.
#
#   tool/conformance.sh                       # http://localhost:8080
#   HOST=http://localhost:3000 tool/conformance.sh
#
# Each run uses a fresh uid, so it can be repeated against the same database.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${HOST:-http://localhost:8080}"
UID_VAL="${UID_VAL:-$(date +%s)$$}"

if ! command -v hurl >/dev/null; then
  echo "hurl is not installed: https://hurl.dev/docs/installation.html" >&2
  exit 1
fi

echo "RealWorld conformance against $HOST (uid=$UID_VAL)"
hurl --test \
  --jobs 1 \
  --variable "host=$HOST" \
  --variable "uid=$UID_VAL" \
  "$ROOT"/spec/realworld-hurl/*.hurl
