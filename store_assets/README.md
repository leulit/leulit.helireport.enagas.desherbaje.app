# Store Assets — Helireport Desherbaje

## Archivos

| Archivo | Uso | Tamaño requerido |
|---|---|---|
| `app_icon_512x512.svg` | Ícono de app en Google Play | Exportar a PNG 512×512 |
| `feature_graphic_1024x500.svg` | Banner en ficha de Play Store | Exportar a PNG 1024×500 |
| `screenshots/` | Capturas de pantalla | PNG, mín. 2 por dispositivo |

## Cómo exportar a PNG

### Opción 1 — Navegador (más fácil)
1. Abre el SVG en Chrome/Safari
2. Clic derecho → "Guardar imagen como" → PNG

### Opción 2 — Online
- https://svgtopng.com — sube el SVG, descarga PNG en el tamaño exacto

### Opción 3 — CLI (si tienes Inkscape instalado)
```bash
inkscape app_icon_512x512.svg --export-png=app_icon_512x512.png -w 512 -h 512
inkscape feature_graphic_1024x500.svg --export-png=feature_graphic_1024x500.png -w 1024 -h 500
```

## Screenshots necesarios
Mínimo 2 capturas de pantalla de la app en dispositivo Android.
Tamaño: entre 320px y 3840px en el lado más corto.
Formato: PNG o JPG.

Capturas recomendadas:
1. Pantalla de login
2. Listado de actividades
3. Mapa de actividades
4. Captura de foto en campo
