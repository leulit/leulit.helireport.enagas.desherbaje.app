#!/bin/bash
set -euo pipefail

# Builds iOS release artifact (IPA) via flutter build ipa and copies it under artifacts/ios.

usage() {
  cat <<'EOF'
Usage: ./build-ios.sh [options]

Options:
  --clean                   Run flutter clean before building.
  --no-codesign             Pass --no-codesign to flutter build ipa.
  --export-options <plist>  Provide an export options plist for code signing.
  -h, --help                Show this help message.
EOF
}

if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "Error: iOS builds require macOS." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found in PATH" >&2
  exit 1
fi

CLEAN=false
NO_CODESIGN=false
EXPORT_PLIST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN=true
      shift
      ;;
    --no-codesign)
      NO_CODESIGN=true
      shift
      ;;
    --export-options)
      if [[ $# -lt 2 ]]; then
        echo "Error: --export-options requires a plist path." >&2
        exit 1
      fi
      EXPORT_PLIST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts/ios"
IPA_DIR="$PROJECT_ROOT/build/ios/ipa"

mkdir -p "$ARTIFACTS_DIR"

cd "$PROJECT_ROOT"

# --- Inyecta HMAC_SECRET desde .env ---
if [ -f .env ]; then
  HMAC_SECRET=$(grep -E '^HMAC_SECRET=' .env | head -1 | cut -d= -f2-)
fi
if [ -z "$HMAC_SECRET" ]; then
  echo "Error: HMAC_SECRET no encontrado en .env" >&2
  exit 1
fi

if [[ "$CLEAN" == true ]]; then
  flutter clean
fi

flutter pub get

BUILD_CMD=(flutter build ipa --release --dart-define-from-file=.env)

if [[ "$NO_CODESIGN" == true ]]; then
  BUILD_CMD+=(--no-codesign)
fi

if [[ -n "$EXPORT_PLIST" ]]; then
  if [[ ! -f "$EXPORT_PLIST" ]]; then
    echo "Error: export options plist not found at $EXPORT_PLIST" >&2
    exit 1
  fi
  BUILD_CMD+=(--export-options-plist "$EXPORT_PLIST")
fi

echo "Running: ${BUILD_CMD[*]}"
"${BUILD_CMD[@]}"

if [[ ! -d "$IPA_DIR" ]]; then
  echo "Error: expected IPA directory not found at $IPA_DIR" >&2
  exit 1
fi

LATEST_IPA=$(ls -t "$IPA_DIR"/*.ipa 2>/dev/null | head -n 1 || true)

if [[ -z "$LATEST_IPA" ]]; then
  echo "Error: no .ipa artifact found in $IPA_DIR" >&2
  exit 1
fi

DEST_PATH="$ARTIFACTS_DIR/$(basename "$LATEST_IPA")"
cp "$LATEST_IPA" "$DEST_PATH"
echo "✔ Copied IPA to $DEST_PATH"

echo "iOS build complete. Artifacts available in artifacts/ios/."
