#!/usr/bin/env bash
# Compiles the Dart web app to JavaScript and assembles packages/conduit_web/build/web,
# which the server serves beside the API.
#
#   tool/build_web.sh           # optimised (-O2)
#   OPT=-O0 tool/build_web.sh   # quicker to compile, easier to debug
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/packages/conduit_web"
OUT="$WEB/build/web"

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$WEB"/web/{index.html,styles.css,icons.css,default-avatar.svg,favicon.svg} "$OUT/"

dart compile js "${OPT:--O2}" --no-source-maps \
  -o "$OUT/main.dart.js" "$WEB/web/main.dart"
rm -f "$OUT/main.dart.js.deps"

echo "built $OUT ($(du -h "$OUT/main.dart.js" | cut -f1) of JavaScript)"
