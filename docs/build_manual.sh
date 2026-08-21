#!/usr/bin/env bash
# Genera el manual de operario en PDF desde docs/manual_v4.html.
# Las capturas se leen de docs/capturas/ (ver LEEME.md).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="$DIR/MANUAL_OPERARIO_HELIREPORT_DESHERBAJE_v4.pdf"
RAW="$DIR/.manual_raw.pdf"

[ -x "$CHROME" ] || { echo "No encuentro Chrome en: $CHROME"; exit 1; }

# virtual-time-budget: da margen a que corra el script que retira los marcos
# punteados de los huecos que ya tienen captura. Sin él Chrome imprime antes.
"$CHROME" --headless \
  --disable-gpu \
  --no-pdf-header-footer \
  --virtual-time-budget=3000 \
  --print-to-pdf="$RAW" \
  "file://$DIR/manual_v4.html"

# Chrome/Skia embebe las capturas casi sin comprimir (un PDF de 20 páginas con
# capturas de iPhone puede pesar 20-25 MB). ghostscript las recomprime a
# 300ppi/JPEG de calidad imprenta — de sobra para pantalla y para imprimir —
# y deja el PDF en una quinta parte. Si no hay gs instalado, se entrega el
# PDF sin optimizar (aviso, no bloquea el build).
if command -v gs >/dev/null 2>&1; then
  gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/printer \
     -dColorImageResolution=300 -dGrayImageResolution=300 -dMonoImageResolution=300 \
     -dDownsampleColorImages=true -dDownsampleGrayImages=true -dDownsampleMonoImages=true \
     -dColorImageDownsampleType=/Bicubic -dGrayImageDownsampleType=/Bicubic \
     -dNOPAUSE -dBATCH -dQUIET \
     -sOutputFile="$OUT" "$RAW"
  rm -f "$RAW"
else
  mv "$RAW" "$OUT"
  echo "⚠ ghostscript (gs) no encontrado: el PDF no se ha optimizado, pesará bastante más."
fi

echo "→ $OUT"

faltan=0
while IFS= read -r f; do
  [ -f "$DIR/capturas/$f" ] || { echo "   falta captura: capturas/$f"; faltan=$((faltan+1)); }
done < <(grep -o 'capturas/[0-9_a-z]*\.png' "$DIR/manual_v4.html" | sed 's|capturas/||' | sort -u)

[ "$faltan" -eq 0 ] && echo "   todas las capturas presentes" || echo "   $faltan captura(s) pendiente(s)"
