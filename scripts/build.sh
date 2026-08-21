#!/usr/bin/env bash
#
# Build Helireport Desherbaje — genera artefactos para publicar en Google Play y/o App Store.
#
# Uso:
#   ./scripts/build.sh android              # AAB para Google Play
#   ./scripts/build.sh ios                  # IPA para App Store / TestFlight
#   ./scripts/build.sh both                 # AAB + IPA
#
# Flags opcionales:
#   --bump             Sube la versión de pubspec.yaml (regla odómetro) antes de construir
#   --no-clean         Omite `flutter clean` (más rápido, builds incrementales)
#   --apk              (android/both) Genera además APK universal
#   --upload           (ios/both) Sube el IPA a App Store Connect (TestFlight) al terminar.
#                      Necesita ASC_KEY_ID + ASC_ISSUER_ID (ver .asc.env / docs/PUBLICAR.md)
#   --upload-only      (ios) NO compila: sube el IPA ya existente en dist/ios para la
#                      versión actual de pubspec.yaml. Para cuando olvidaste --upload.
#
# Artefactos:
#   dist/android/helireport_desherbaje-<version>+<build>.aab [y .apk]
#   dist/ios/helireport_desherbaje-<version>+<build>.ipa

set -euo pipefail

# --- Ubicación proyecto --------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# --- Colores -------------------------------------------------------------------
C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_BLUE='\033[0;34m'; C_RESET='\033[0m'
log()   { echo -e "${C_GREEN}▶${C_RESET} $*"; }
info()  { echo -e "${C_BLUE}ℹ${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }
error() { echo -e "${C_RED}✗${C_RESET} $*" >&2; exit 1; }

usage() {
  sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# --- Parseo args ---------------------------------------------------------------
TARGET="${1:-}"
[[ -z "$TARGET" ]] && usage 1
shift || true

case "$TARGET" in
  android|ios|both) ;;
  -h|--help)        usage 0 ;;
  *) error "Target desconocido: '$TARGET' (usa: android | ios | both)" ;;
esac

SKIP_CLEAN=false
BUILD_APK=false
BUMP=false
UPLOAD=false
UPLOAD_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --bump)      BUMP=true ;;
    --no-clean)  SKIP_CLEAN=true ;;
    --apk)       BUILD_APK=true ;;
    --upload)    UPLOAD=true ;;
    --upload-only) UPLOAD_ONLY=true; UPLOAD=true ;;
    -h|--help)   usage 0 ;;
    *)           error "Flag desconocida: $arg" ;;
  esac
done

[[ "$UPLOAD" == true && "$TARGET" == "android" ]] && error "--upload solo aplica a iOS (Google Play no acepta subida sin API key de servicio)"
[[ "$UPLOAD_ONLY" == true && "$BUMP" == true ]] && error "--upload-only no admite --bump: subiría una versión que nadie ha construido"

# Credenciales de App Store Connect: fichero .asc.env (gitignored) o variables ya exportadas.
if $UPLOAD; then
  # Variables ya exportadas mandan; el fichero solo rellena lo que falte.
  [[ -z "${ASC_KEY_ID:-}" && -f .asc.env ]] && source .asc.env
  ASC_KEY_ID="${ASC_KEY_ID:-}"; ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
  [[ -n "$ASC_KEY_ID" && -n "$ASC_ISSUER_ID" ]] || \
    error "--upload necesita ASC_KEY_ID y ASC_ISSUER_ID (créalos en .asc.env, ver docs/PUBLICAR.md)"
  [[ -f "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" ]] || \
    error "Falta ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
fi

# --- Prerrequisitos comunes ----------------------------------------------------
command -v flutter >/dev/null || error "flutter no está en PATH"

# HMAC_SECRET viaja por --dart-define-from-file=.env. Sin él el binario sale con
# el placeholder de AppConfig y el backend responde 401 en TODA la API.
[[ -f .env ]] || error "Falta .env con HMAC_SECRET (el build saldría con placeholder → 401)"
grep -qE '^HMAC_SECRET=.+' .env || error ".env no define HMAC_SECRET"
DEFINES=(--dart-define-from-file=.env)

# El bump va ANTES de leer la versión: el artefacto debe llevar la nueva.
if $BUMP; then
  log "bump versión"
  "$SCRIPT_DIR/bump-version.sh"
fi

VERSION_LINE=$(grep '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE##*+}"
ARTIFACT_BASE="helireport_desherbaje-${VERSION_NAME}+${BUILD_NUMBER}"

log "Target: $TARGET — versión: $VERSION_NAME (build $BUILD_NUMBER)"

upload_ipa() {
  local ipa="$1"
  [[ -f "$ipa" ]] || error "No existe $ipa (constrúyelo con: ./scripts/build.sh ios)"
  log "[iOS] subiendo a App Store Connect (altool)…"
  xcrun altool --upload-app --type ios \
    --file "$ipa" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
    || error "Falló la subida. El IPA sigue en $ipa: súbelo con Transporter."
  log "[iOS] subido. Aparece en TestFlight en ~5-15 min."
}

if $UPLOAD_ONLY; then
  upload_ipa "dist/ios/${ARTIFACT_BASE}.ipa"
  exit 0
fi

# Borrador de "Novedades" para la ficha de tienda. Idempotente: si el fichero de
# esta versión ya existe, no lo pisa (puede estar ya redactado a mano).
NOTES_FILE="store_assets/texts/whatsnew/es-ES_${VERSION_NAME}.txt"
"$SCRIPT_DIR/release-notes.sh" "$VERSION_NAME" || warn "No se pudo generar el borrador de novedades (sigo con el build)"

# --- Limpieza + deps (una sola vez, compartida) --------------------------------
if ! $SKIP_CLEAN; then
  log "flutter clean"
  flutter clean >/dev/null
fi
log "flutter pub get"
flutter pub get >/dev/null

# --- Funciones por plataforma --------------------------------------------------
build_android() {
  [[ -f "android/key.properties" ]] || error "Falta android/key.properties"
  [[ -f "android/helireport-desherbaje-release.jks" ]] || error "Falta keystore .jks"

  local dist_dir="dist/android"
  mkdir -p "$dist_dir"

  log "[Android] flutter build appbundle --release"
  flutter build appbundle --release "${DEFINES[@]}"

  local aab_src="build/app/outputs/bundle/release/app-release.aab"
  [[ -f "$aab_src" ]] || error "No se generó AAB en $aab_src"
  local aab_out="$dist_dir/${ARTIFACT_BASE}.aab"
  cp "$aab_src" "$aab_out"
  log "[Android] AAB: $aab_out ($(du -h "$aab_out" | cut -f1))"

  if $BUILD_APK; then
    log "[Android] flutter build apk --release"
    flutter build apk --release "${DEFINES[@]}"
    local apk_src="build/app/outputs/flutter-apk/app-release.apk"
    local apk_out="$dist_dir/${ARTIFACT_BASE}.apk"
    cp "$apk_src" "$apk_out"
    log "[Android] APK: $apk_out ($(du -h "$apk_out" | cut -f1))"
  fi
}

sync_ios_version() {
  local pbxproj="ios/Runner.xcodeproj/project.pbxproj"
  # Runner target uses $(FLUTTER_BUILD_NUMBER) / $(FLUTTER_BUILD_NAME) — injected by flutter build.
  # RunnerTests configs have hardcoded values; keep them in sync so Xcode doesn't show stale numbers.
  sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${VERSION_NAME};/g" "$pbxproj"
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "$pbxproj"
  info "[iOS] project.pbxproj actualizado → ${VERSION_NAME}+${BUILD_NUMBER}"
}

build_ios() {
  [[ "$(uname)" == "Darwin" ]] || error "Build iOS solo funciona en macOS"
  command -v xcodebuild >/dev/null || error "xcodebuild no está en PATH (instala Xcode)"

  local dist_dir="dist/ios"
  mkdir -p "$dist_dir"

  sync_ios_version

  log "[iOS] pod install"
  (cd ios && pod install --repo-update >/dev/null)

  log "[iOS] flutter build ipa --release --export-method app-store"
  flutter build ipa --release --export-method app-store "${DEFINES[@]}"

  local ipa_src
  ipa_src=$(ls build/ios/ipa/*.ipa 2>/dev/null | head -n1 || true)
  [[ -n "$ipa_src" && -f "$ipa_src" ]] || error "No se generó IPA (revisa signing en Xcode)"
  local ipa_out="$dist_dir/${ARTIFACT_BASE}.ipa"
  cp "$ipa_src" "$ipa_out"
  log "[iOS] IPA: $ipa_out ($(du -h "$ipa_out" | cut -f1))"

  $UPLOAD && upload_ipa "$ipa_out"
}

# --- Ejecución -----------------------------------------------------------------
case "$TARGET" in
  android) build_android ;;
  ios)     build_ios ;;
  both)
    build_android
    build_ios
    ;;
esac

# --- Resumen -------------------------------------------------------------------
echo
echo -e "${C_GREEN}✓ Build completado${C_RESET}"
echo

if [[ "$TARGET" == "android" || "$TARGET" == "both" ]]; then
  cat <<EOF
$(printf "%b" "${C_BLUE}")Android$(printf "%b" "${C_RESET}") — subir a Google Play Console:
  1. https://play.google.com/console → Helireport Desherbaje
  2. Testing → Internal testing (o el track que toque) → Create new release
  3. Sube: dist/android/${ARTIFACT_BASE}.aab
  4. Review release → Start rollout

EOF
fi

if [[ ( "$TARGET" == "ios" || "$TARGET" == "both" ) && "$UPLOAD" == true ]]; then
  cat <<EOF
$(printf "%b" "${C_BLUE}")iOS$(printf "%b" "${C_RESET}") — IPA ya subido a App Store Connect.
  Revisa https://appstoreconnect.apple.com → TestFlight (tarda 5-15 min en procesar).

EOF
elif [[ "$TARGET" == "ios" || "$TARGET" == "both" ]]; then
  cat <<EOF
$(printf "%b" "${C_BLUE}")iOS$(printf "%b" "${C_RESET}") — subir a App Store Connect:
  Opción A (gráfica): Abre Transporter (Mac App Store) → arrastra dist/ios/${ARTIFACT_BASE}.ipa
  Opción B (CLI):
     xcrun altool --upload-app --type ios \\
       --file dist/ios/${ARTIFACT_BASE}.ipa \\
       --apiKey <ASC_KEY_ID> --apiIssuer <ASC_ISSUER_ID>
  Tras ~5-15 min el build aparece en TestFlight → Internal Testing.

EOF
fi

if [[ -f "$NOTES_FILE" ]]; then
  cat <<EOF
$(printf "%b" "${C_BLUE}")Novedades$(printf "%b" "${C_RESET}") — texto para la caja "Novedades de esta versión":
  Fichero: ${NOTES_FILE}
  Revísalo (los subjects vienen de commits técnicos) y pégalo en:
    · App Store Connect → versión → "Novedades de esta versión"
    · Play Console → release → "Notas de la versión"

EOF
fi

if ! $BUMP; then
  warn "Versión usada: ${VERSION_NAME}+${BUILD_NUMBER}. El próximo build para tienda necesita otra: usa --bump."
fi

# Abrir Finder en dist/ (macOS)
if command -v open >/dev/null; then
  case "$TARGET" in
    android) open dist/android ;;
    ios)     open dist/ios ;;
    both)    open dist ;;
  esac
fi
