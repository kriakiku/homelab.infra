#!/bin/sh
set -eu

HOMARR_URL="${HOMARR_URL:-http://homarr.network.svc.cluster.local:7575}"
BOARDS_DIR="${BOARDS_DIR:-/seed/boards}"

if [ -z "${HOMARR_API_KEY:-}" ]; then
  echo "HOMARR_API_KEY is not set — skipping board seeding."
  echo "After first OIDC login, create an API key in Homarr (Management → Tools → API)"
  echo "and add it to homarr-secret (HOMARR_API_KEY), then re-run this job."
  exit 0
fi

echo "Waiting for Homarr at ${HOMARR_URL}..."
for i in $(seq 1 60); do
  if curl -sf "${HOMARR_URL}/api/health/live" >/dev/null 2>&1; then
    echo "Homarr is ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Homarr did not become ready in time."
    exit 1
  fi
  sleep 5
done

echo "Fetching existing boards..."
existing=$(curl -sS \
  -H "ApiKey: ${HOMARR_API_KEY}" \
  "${HOMARR_URL}/api/trpc/board.getAllBoards" \
  2>/dev/null || echo "")

imported=0
skipped=0
failed=0

for board_file in "${BOARDS_DIR}"/*.json; do
  [ -f "$board_file" ] || continue

  display_name=$(grep -A3 '"configProperties"' "$board_file" | grep '"name"' | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

  if echo "$existing" | grep -Fq "\"name\":\"${display_name}\"" 2>/dev/null; then
    echo "Board '${display_name}' already exists — skipping."
    skipped=$((skipped + 1))
    continue
  fi

  echo "Importing board '${display_name}' from ${board_file}..."

  config_json=$(printf '{"onlyImportApps":false,"sidebarBehaviour":"last-section","name":"%s"}' "$display_name")

  http_code=$(curl -sS -o /tmp/homarr-import-response.json -w "%{http_code}" \
    -H "ApiKey: ${HOMARR_API_KEY}" \
    -F "file=@${board_file};type=application/json" \
    -F "configuration=${config_json};type=application/json" \
    "${HOMARR_URL}/api/trpc/board.importOldmarrConfig" \
    || true)

  if [ "$http_code" = "200" ] && ! grep -q '"error"' /tmp/homarr-import-response.json 2>/dev/null; then
    echo "Imported '${display_name}'."
    imported=$((imported + 1))
  else
    echo "Failed to import '${display_name}' (HTTP ${http_code}):"
    cat /tmp/homarr-import-response.json 2>/dev/null || true
    echo
    failed=$((failed + 1))
  fi
done

echo "Board seeding complete: ${imported} imported, ${skipped} skipped, ${failed} failed."
[ "$failed" -eq 0 ]
