#!/usr/bin/env bash
#
# Genera el borrador de "Novedades" (App Store What's New / Google Play release notes)
# para la versión actual de pubspec.yaml.
#
# Uso:
#   ./scripts/release-notes.sh            # versión leída de pubspec.yaml
#   ./scripts/release-notes.sh 1.2.0      # versión explícita
#   ./scripts/release-notes.sh --force    # regenera aunque el fichero ya exista
#
# Salida: store_assets/texts/whatsnew/es-ES_<version>.txt  (listo para pegar en la tienda)
#
# El borrador sale de los commits Conventional Commits (feat/fix) desde el último
# cambio de la línea `version:` en pubspec.yaml. NO es texto final: los subjects son
# técnicos y hay que reescribirlos en lenguaje de operador antes de publicar.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_BLUE='\033[0;34m'; C_RESET='\033[0m'
log()  { echo -e "${C_GREEN}▶${C_RESET} $*"; }
info() { echo -e "${C_BLUE}ℹ${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }

FORCE=false
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -h|--help) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) VERSION="$arg" ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION=$(grep -E '^version:' pubspec.yaml | head -1 | sed -E 's/^version:[[:space:]]*//')
  VERSION="${VERSION%%+*}"
fi
[[ -n "$VERSION" ]] || { echo "Error: no se pudo determinar la versión" >&2; exit 1; }

OUT_DIR="store_assets/texts/whatsnew"
OUT="$OUT_DIR/es-ES_${VERSION}.txt"
mkdir -p "$OUT_DIR"

if [[ -f "$OUT" && "$FORCE" != true ]]; then
  info "Ya existe (no se toca): $OUT"
  info "Regenera con: ./scripts/release-notes.sh --force"
  exit 0
fi

# Ancla = commit más reciente que cambió la línea `version:`. Todo lo posterior es
# lo que entra en esta versión. Sin tags de release (no se crean sin autorización),
# esta es la única marca de corte fiable en el historial.
# ponytail: si el bump ya está commiteado, el ancla es ESE commit y el rango sale
# vacío — por eso se genera antes de commitear el bump (build.sh lo llama tras --bump).
ANCHOR=$(git log --format=%H -G'^version:' -- pubspec.yaml 2>/dev/null | sed -n '1p' || true)
if [[ -n "$ANCHOR" ]]; then
  RANGE="${ANCHOR}..HEAD"
else
  warn "Sin ancla de versión en el historial; uso los últimos 20 commits."
  RANGE="HEAD~20..HEAD"
fi

# Solo feat/fix: el resto (chore, docs, test, refactor, build, ci, style) no es
# visible para el operador, y los subjects sin prefijo convencional son ruido.
# ponytail: sin mapfile — macOS trae bash 3.2 y no lo tiene.
SUBJECTS=$(git log --format='%s' "$RANGE" 2>/dev/null || true)
FEATS=$(printf '%s\n' "$SUBJECTS" | grep -E '^feat(\([^)]*\))?!?:' | sed -E 's/^feat(\([^)]*\))?!?:[[:space:]]*//' || true)
FIXES=$(printf '%s\n' "$SUBJECTS" | grep -E '^fix(\([^)]*\))?!?:'  | sed -E 's/^fix(\([^)]*\))?!?:[[:space:]]*//'  || true)

{
  echo "Novedades de la versión ${VERSION}"
  echo
  [[ -n "$FEATS" ]] && printf '%s\n' "$FEATS" | sed 's/^/• Nuevo: /'
  [[ -n "$FIXES" ]] && printf '%s\n' "$FIXES" | sed 's/^/• Corregido: /'
  if [[ -z "$FEATS" && -z "$FIXES" ]]; then
    echo "• (sin commits feat/fix en el rango — describe aquí los cambios a mano)"
  fi
  echo "• Mejoras de estabilidad y rendimiento."
} > "$OUT"

CHARS=$(wc -m < "$OUT" | tr -d ' ')
log "Novedades: $OUT (${CHARS} caracteres)"

# App Store permite 4000; Google Play corta en 500. El mismo texto sirve para ambas
# tiendas solo si cabe en el límite menor.
if (( CHARS > 500 )); then
  warn "Supera los 500 caracteres de Google Play (App Store admite 4000). Recorta antes de publicar."
fi

warn "BORRADOR: los subjects son técnicos. Reescríbelos en lenguaje de operador antes de pegarlo en la tienda."
