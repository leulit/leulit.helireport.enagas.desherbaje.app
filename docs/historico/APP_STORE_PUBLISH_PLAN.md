> **Archivado el 2026-08-19.** Este es el diario del release `1.0.3+103` (mayo 2026); la versión actual es `1.1.9+119` y este plan ya no refleja el estado del proyecto. El manual vivo de publicación es [`docs/PUBLICAR.md`](../PUBLICAR.md) (datos de cuenta, checklist de metadata y plantilla de notas para el revisor migrados allí).

# Plan de publicación — App Store (iOS)

**App**: Helireport Desherbaje  
**Bundle ID**: `com.leulit.enagas.helireport-desherbaje`  
**Versión objetivo**: `1.0.3` (build `103`)  
**Fecha inicio**: 2026-05-04

---

## Estado rápido

| Fase | Estado |
|---|---|
| Fase 1 — Prerrequisitos (cuenta y certificados) | ⬜ Pendiente |
| Fase 2 — Preparar proyecto Xcode | ⬜ Pendiente |
| Fase 3 — Build para distribución | ⬜ Pendiente |
| Fase 4 — Subir a App Store Connect | ⬜ Pendiente |
| Fase 5 — Configurar el release | ⬜ Pendiente |
| Fase 6 — Review de Apple | ⬜ Pendiente |

---

## Fase 1 — Prerrequisitos

### Cuenta Apple Developer
- [ ] Cuenta activa en developer.apple.com ($99/año)
- [ ] Tipo organización confirmado (requiere D-U-N-S number si es empresa)
- [ ] Acceso de admin o App Manager para el equipo

### Bundle ID
- [x] Registrar `com.leulit.enagas.helireport-desherbaje` en **Certificates, IDs & Profiles → Identifiers** ✅
  - Tipo: App IDs → App (Explicit)
  - Description: `Helireport Desherbaje`
  - Team ID: `XZ784KD9U4`
  - Nota: Background Modes ya no aparece en esta lista — se configura solo desde Xcode (ya hecho)
- [x] Crear la app en **App Store Connect → My Apps → New App** ✅
  - Platform: iOS
  - Name: `Helireport Desherbaje`
  - Primary Language: Spanish (Spain)
  - Bundle ID: `com.leulit.enagas.helireport-desherbaje`
  - SKU: `helireport-desherbaje-01`
  - User Access: Acceso ilimitado

---

## Fase 2 — Preparar proyecto Xcode

### Versión
- [x] Sincronizar `MARKETING_VERSION` → `1.0.3` en `ios/Runner.xcodeproj/project.pbxproj` ✅
- [x] Sincronizar `CURRENT_PROJECT_VERSION` → `103` ✅

> Runner Debug/Release/Profile ya usaban `$(FLUTTER_BUILD_NUMBER)` (dinámico). Se corrigieron las 3 configuraciones de RunnerTests que tenían `1.0` / `1` hardcodeados.

### Signing
- [x] Target `Runner` → **Signing & Capabilities** ✅
  - Automatically manage signing: ✅
  - Team: organización Apple asignada
  - Bundle Identifier: `com.leulit.enagas.helireport-desherbaje`

### Background Modes capability
- [x] Añadir capability **Background Modes** en Xcode ✅
  - ✅ Location updates
  - ✅ Background fetch
  - ✅ Background processing

> `SystemCapabilities.com.apple.BackgroundModes` añadido en `TargetAttributes` del `project.pbxproj`.  
> `UIBackgroundModes` en `Info.plist` ya estaban correctos. Las tres `NSLocation*UsageDescription` presentes. ✅

---

## Fase 3 — Build para distribución

```bash
./scripts/build.sh ios
```

- [x] Build completado sin errores ✅
- [x] `.ipa` generado en `dist/ios/helireport_desherbaje-1.0.3+103.ipa` (20 MB) ✅

> Validaciones del build: Version 1.0.3 · Build 103 · Bundle `com.leulit.enagas.helireport-desherbaje` · Deployment target 13.0  
> Aviso menor: Launch image es el placeholder de Flutter — reemplazar antes del release definitivo.  
> Aviso CocoaPods (Profile xcconfig): conocido en proyectos Flutter, no afecta al IPA.

---

## Fase 4 — Subir a App Store Connect

Método elegido: **Transporter** (App gratuita del Mac App Store, recomendado para primera subida)

- [x] Descargar Transporter desde el Mac App Store ✅
- [x] Subir el `.ipa` → pulsar **Deliver** ✅
  - Delivery UUID: `8765fa45-872f-4327-9220-d53dbac4faa3`
  - Transferidos 21.6 MB en 8.3s a 20.8 Mbps
  - Estado final: `UPLOAD SUCCEEDED with no errors`
- [ ] Esperar procesamiento en App Store Connect (5-15 min) — estado actual: `PROCESSING`
- [ ] Build aparece en la sección **TestFlight** o en la pestaña del release

---

## Fase 5 — Configurar el release en App Store Connect

### Metadata obligatoria
- [ ] **Screenshots** — mínimo requerido:
  - iPhone 6.5" (iPhone 14 Plus / 15 Plus) — **1284×2778px**
    - Capturas originales: `store_assets/screenshots/` (1170×2532, iPhone 16e)
    - Redimensionadas a 1284×2778: `store_assets/screenshots_65inch/` ✅
    - Subir mediante **drag & drop** en App Store Connect (el selector de archivos puede fallar)
    - El modal "Idiomas, capturas de pantalla…" es informativo — pulsar Aceptar y continuar
  - iPhone 5.5" (iPhone 8 Plus) — si se declara soporte a versiones antiguas
  - iPad 12.9" — solo si la app soporta iPad
- [ ] **Nombre de la app** (30 chars máx)
- [ ] **Subtítulo** (30 chars máx, opcional)
- [ ] **Descripción** (4000 chars máx)
- [ ] **Keywords** (100 chars máx, separados por coma)
- [ ] **Support URL** — URL accesible públicamente
- [ ] **Marketing URL** — opcional
- [ ] **Privacy Policy URL** — **obligatorio** (la app recoge ubicación)

### Privacidad ⚠️ obligatorio para apps con ubicación
- [ ] App Store Connect → **App Privacy** → **Get Started**
  - **Location** → Precise Location → ✅ Used → Purpose: App Functionality
  - **Location** → Background Location → ✅ Used → Purpose: App Functionality
- [ ] Confirmar que no se recopilan datos vinculados al usuario más allá de los necesarios

### Seleccionar el build
- [ ] Pestaña del release → sección **Build** → seleccionar `1.0.3 (103)`

### App Review Information
- [ ] Credenciales de prueba (usuario + contraseña) para el revisor de Apple
- [ ] Teléfono de contacto
- [ ] Notas para el revisor (ver plantilla en Fase 6)

---

## Fase 6 — Envío a revisión de Apple

### Notas para el revisor (copiar en App Store Connect → Notes for Reviewer)

```
Esta app es una herramienta de campo para operadores de gasoducto de Enagas.
Los operadores registran su ruta GPS durante jornadas de trabajo en campo
(desherbaje de segmentos de gasoducto). La ubicación en background es necesaria
para que el tracking continúe cuando el operador guarda el teléfono en el bolsillo
durante la jornada.

La app NO se distribuye al público general — es una herramienta B2B interna
para empleados y contratistas de Enagas.
```

### Envío
- [ ] Revisar **completeness checklist** de App Store Connect (sección Prepare for Submission)
- [ ] Pulsar **Submit for Review**
- [ ] Confirmar preguntas de exportación (cifrado: la app usa HTTPS estándar → responder Sí al algoritmo estándar, No a cifrado propietario)

### Post-revisión
- [ ] Si Apple rechaza por **background location**: responder en la misma thread con la justificación de negocio de arriba
- [ ] Si Apple aprueba: **Release** manual o automático según configuración

---

## Notas y decisiones

| Fecha | Nota |
|---|---|
| 2026-05-04 | Plan creado. Info.plist ya configurado correctamente (UIBackgroundModes, NSLocation descriptions). |
| 2026-05-04 | Bundle ID unificado: las 6 configuraciones de `project.pbxproj` (Runner Debug/Release/Profile + RunnerTests Debug/Release/Profile) apuntan ahora a `com.leulit.enagas.helireport-desherbaje`, igual que Android. |
| 2026-05-04 | Versión sincronizada: RunnerTests `MARKETING_VERSION = 1.0.3`, `CURRENT_PROJECT_VERSION = 103`. Runner target ya usaba `$(FLUTTER_BUILD_NUMBER)` dinámico. |
| 2026-05-04 | Screenshots redimensionados: iPhone 16e produce 1170×2532; App Store pide 1284×2778 para 6.5". Generados con `sips` sin distorsión en `store_assets/screenshots_65inch/`. Subir via drag & drop. |

---

## Referencias

- [App Store Connect](https://appstoreconnect.apple.com)
- [Apple Developer — Identifiers](https://developer.apple.com/account/resources/identifiers/list)
- [Transporter (Mac App Store)](https://apps.apple.com/app/transporter/id1450874784)
- [Human Interface Guidelines — App Store screenshots](https://developer.apple.com/design/human-interface-guidelines/app-store)
