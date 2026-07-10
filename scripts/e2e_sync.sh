#!/usr/bin/env bash
# Build and launch the Vellum server against a throwaway database, then run the
# tagged Flutter end-to-end sync test against it. Used by the `e2e` CI job and
# runnable locally (`bash scripts/e2e_sync.sh`). Requires cargo and flutter.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${VELLUM_PORT:-3999}"
WORK="$(mktemp -d)"

cleanup() {
  [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "Building server…"
(cd "$ROOT/server" && cargo build --quiet)

echo "Launching server on :$PORT (db=$WORK)…"
VELLUM_DB="$WORK/vellum.db" VELLUM_DATA_DIR="$WORK/data" VELLUM_PORT="$PORT" \
  "$ROOT/server/target/debug/vellum-server" >"$WORK/server.log" 2>&1 &
SRV=$!

echo "Waiting for /health…"
for _ in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 0.5
done
if [ -z "${ok:-}" ]; then
  echo "server did not come up; log:" >&2
  cat "$WORK/server.log" >&2
  exit 1
fi

echo "Running e2e sync test…"
cd "$ROOT/app"
flutter pub get
VELLUM_E2E_URL="http://127.0.0.1:$PORT" flutter test --tags e2e
