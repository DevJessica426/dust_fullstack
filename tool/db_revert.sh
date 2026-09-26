#!/usr/bin/env bash
# Reverts the most recently applied migration(s) using their SQLx-style
# `.down.sql` files.
#
#   tool/db_revert.sh        # the latest one
#   tool/db_revert.sh 3      # the latest three, newest first
#
# The server applies `.up.sql` files at startup through Dust, which records
# each in `__dust_schema_migrations` and never runs a `.down.sql`. `sqlx migrate
# revert` can't undo those either: SQLx keeps its own `_sqlx_migrations` table.
# This runs the matching down migration and deletes Dust's record in one
# transaction, so the next server start re-applies it cleanly.
#
# TODO(dust): replace this with Dust's own revert command if one ships. No
# issue asks for it yet; dust#257 only keeps `.down.sql` files for future
# downgrade tooling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/packages/conduit_server/migrations"
COUNT="${1:-1}"
URL="${DATABASE_URL:-postgres://conduit:conduit@localhost:5432/conduit?sslmode=disable}"
# psql reads libpq URLs, which do not take the sslmode the Dart driver needs
# spelled out; keep the rest of the URL as given.
PSQL_URL="${URL%%\?*}"

[[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "usage: $0 [count]" >&2; exit 2; }

applied=$(psql "$PSQL_URL" -Atc \
  "SELECT name FROM __dust_schema_migrations ORDER BY name DESC LIMIT $COUNT")
[ -n "$applied" ] || { echo "nothing to revert"; exit 0; }

for up in $applied; do
  down="$DIR/${up%.up.sql}.down.sql"
  if [ ! -f "$down" ]; then
    echo "no down migration for $up (expected $down)" >&2
    exit 1
  fi
  psql "$PSQL_URL" -v ON_ERROR_STOP=1 -q --single-transaction \
    -f "$down" \
    -c "DELETE FROM __dust_schema_migrations WHERE name = '$up'"
  echo "reverted ${up%.up.sql}"
done
