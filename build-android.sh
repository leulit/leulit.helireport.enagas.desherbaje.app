#!/bin/bash
set -euo pipefail

# Builds Android release artifacts (AAB + APK) and copies them under artifacts/android.

usage() {
  cat <<'EOF'
Usage: ./build-android.sh [options]

Options:
  --bump        Increment pubspec version (odometer rule) before building.
  --clean       Run flutter clean before building.
  --skip-apk    Skip generating the release APK.
  --skip-aab    Skip generating the release App Bundle.
  -h, --help    Show this help message.
EOF
}

CLEAN=false
BUILD_APK=true
BUILD_AAB=true
BUMP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      BUMP=true
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    --skip-apk)
      BUILD_APK=false
      shift
      ;;
    --skip-aab)
      BUILD_AAB=false
      shift
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

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts/android"
AAB_SOURCE="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
APK_SOURCE="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"

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

if [[ "$BUMP" == true ]]; then
  "$SCRIPT_DIR/bump-version.sh"
fi

if [[ "$CLEAN" == true ]]; then
  flutter clean
fi

flutter pub get

if [[ "$BUILD_AAB" == true ]]; then
  echo "Building Android App Bundle (.aab)..."
  flutter build appbundle --release --dart-define-from-file=.env
  if [[ ! -f "$AAB_SOURCE" ]]; then
    echo "Error: expected artifact not found at $AAB_SOURCE" >&2
    exit 1
  fi
  cp "$AAB_SOURCE" "$ARTIFACTS_DIR/app-release.aab"
  echo "✔ Copied App Bundle to artifacts/android/app-release.aab"
fi

if [[ "$BUILD_APK" == true ]]; then
  echo "Building Android APK (.apk)..."
  flutter build apk --release --dart-define-from-file=.env
  if [[ ! -f "$APK_SOURCE" ]]; then
    echo "Error: expected artifact not found at $APK_SOURCE" >&2
    exit 1
  fi
  cp "$APK_SOURCE" "$ARTIFACTS_DIR/app-release.apk"
  echo "✔ Copied APK to artifacts/android/app-release.apk"
fi

echo "Android build complete. Artifacts available in artifacts/android/."
