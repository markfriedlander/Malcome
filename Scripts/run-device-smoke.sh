#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Malcome.xcodeproj"
SCHEME="Malcome"
BUNDLE_ID="com.MarkFriedlander.Malcome"
DERIVED_DATA="${DERIVED_DATA:-/tmp/MalcomeDeviceDerived}"
VERIFY_RUNTIME="${VERIFY_RUNTIME:-1}"
DEVICE_ID="${DEVICE_ID:-${1:-}}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "Usage: DEVICE_ID=<device-id> $0"
  echo "   or: $0 <device-id>"
  exit 1
fi

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/Malcome.app"
RUNTIME_DIR="${RUNTIME_DIR:-/tmp/malcome-device-smoke}"

echo "== Build =="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH"
  exit 1
fi

echo
echo "== Install =="
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo
echo "== Launch =="
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo
echo "== Process Check =="
xcrun devicectl device info processes --device "$DEVICE_ID" | rg "$BUNDLE_ID|Malcome" || true

if [[ "$VERIFY_RUNTIME" == "1" ]]; then
  sleep 5

  mkdir -p "$RUNTIME_DIR"
  rm -f "$RUNTIME_DIR"/malcome.sqlite "$RUNTIME_DIR"/malcome.sqlite-shm "$RUNTIME_DIR"/malcome.sqlite-wal

  echo
  echo "== Runtime Files =="
  xcrun devicectl device info files \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --subdirectory "Library/Application Support/Malcome"

  echo
  echo "== Runtime DB Copy =="
  xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support/Malcome/malcome.sqlite" \
    --destination "$RUNTIME_DIR/malcome.sqlite"

  xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support/Malcome/malcome.sqlite-shm" \
    --destination "$RUNTIME_DIR/malcome.sqlite-shm" || true

  xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support/Malcome/malcome.sqlite-wal" \
    --destination "$RUNTIME_DIR/malcome.sqlite-wal" || true

  echo
  echo "== Runtime DB Summary =="
  sqlite3 "$RUNTIME_DIR/malcome.sqlite" <<'SQL'
.timeout 2000
select 'sources', count(*) from source;
select 'snapshots', count(*) from snapshot;
select 'observations', count(*) from observation;
select 'signals', count(*) from signal_candidate;
select 'briefs', count(*) from brief;
SQL

  sources_count="$(sqlite3 "$RUNTIME_DIR/malcome.sqlite" "select count(*) from source;")"
  snapshots_count="$(sqlite3 "$RUNTIME_DIR/malcome.sqlite" "select count(*) from snapshot;")"
  observations_count="$(sqlite3 "$RUNTIME_DIR/malcome.sqlite" "select count(*) from observation;")"
  briefs_count="$(sqlite3 "$RUNTIME_DIR/malcome.sqlite" "select count(*) from brief;")"

  echo
  echo "== Runtime Assertions =="
  echo "sources: $sources_count"
  echo "snapshots: $snapshots_count"
  echo "observations: $observations_count"
  echo "briefs: $briefs_count"

  if [[ "$sources_count" -lt 1 ]]; then
    echo "Device smoke failed: no sources were present in the on-device database."
    exit 1
  fi

  if [[ "$snapshots_count" -lt 1 ]]; then
    echo "Device smoke failed: the app launched but no snapshots were recorded on device."
    exit 1
  fi

  if [[ "$observations_count" -lt 1 ]]; then
    echo "Device smoke failed: the app launched but no observations were stored on device."
    exit 1
  fi

  if [[ "$briefs_count" -lt 1 ]]; then
    echo "Device smoke failed: the app launched but no brief was stored on device."
    exit 1
  fi
fi

echo
echo "Device smoke completed for $BUNDLE_ID on $DEVICE_ID"
