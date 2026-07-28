#!/usr/bin/env bash
# Genera el manual de operario en PDF desde docs/manual_v3.html.
# Las capturas se leen de docs/capturas/ (ver LEEME.md).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="$DIR/MANUAL_OPERARIO_HELIREPORT_DESHERBAJE_v3.pdf"

[ -x "$CHROME" ] || { echo "No encuentro Chrome en: $CHROME"; exit 1; }

# virtual-time-budget: da margen a que corra el script que retira los marcos
# punteados de los huecos que ya tienen captura. Sin él Chrome imprime antes.
"$CHROME" --headless \
  --disable-gpu \
  --no-pdf-header-footer \
  --virtual-time-budget=3000 \
  --print-to-pdf="$OUT" \
  "file://$DIR/manual_v3.html"

echo "→ $OUT"

faltan=0
while IFS= read -r f; do
  [ -f "$DIR/capturas/$f" ] || { echo "   falta captura: capturas/$f"; faltan=$((faltan+1)); }
done < <(grep -o 'capturas/[0-9_a-z]*\.png' "$DIR/manual_v3.html" | sed 's|capturas/||' | sort -u)

[ "$faltan" -eq 0 ] && echo "   todas las capturas presentes" || echo "   $faltan captura(s) pendiente(s)"
