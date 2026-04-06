#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR%/}/malcome-pipeline-check.XXXXXX")"
BIN="$BUILD_DIR/malcome-pipeline-check"
DB="$BUILD_DIR/malcome.sqlite"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

swiftc \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -parse-as-library \
  -lsqlite3 \
  -o "$BIN" \
  "$ROOT/Tools/MalcomePipelineCheck/main.swift" \
  "$ROOT/Malcome/App/AppContainer.swift" \
  "$ROOT/Malcome/Data/AppRepository.swift" \
  "$ROOT/Malcome/Domain/Models.swift" \
  "$ROOT/Malcome/Engine/BriefComposer.swift" \
  "$ROOT/Malcome/Engine/SignalEngine.swift" \
  "$ROOT/Malcome/Services/HTMLSupport.swift" \
  "$ROOT/Malcome/Services/SourcePipeline.swift" \
  "$ROOT/Malcome/Services/SourceRegistry.swift"

MALCOME_STORAGE_PATH="$DB" "$BIN" "$@"
