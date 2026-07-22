# Publicar una versión nueva

App: **Helireport Desherbaje** — `com.leulit.enagas.helireport_desherbaje`

---

## Antes de empezar (solo la primera vez)

| Requisito | Cómo se comprueba |
|---|---|
| `flutter` en PATH | `flutter --version` |
| Fichero `.env` con `HMAC_SECRET` en la raíz | `grep HMAC_SECRET .env` |
| `android/key.properties` | `ls android/key.properties` |
| `android/helireport-desherbaje-release.jks` | `ls android/*.jks` |
| Xcode instalado (solo iOS) | `xcodebuild -version` |
| CocoaPods (solo iOS) | `pod --version` |
| Cuenta con acceso a Google Play Console y App Store Connect | — |

Si falta `.env`, el build aborta. Sin él la app se compila con un secreto falso y **el backend rechaza todo con 401**.

---

## Publicar en Google Play

### 1. Construir

```bash
./scripts/build.sh android --bump
```

Sale: `dist/android/helireport_desherbaje-<version>+<build>.aab`

### 2. Subir

1. Abrir https://play.google.com/console
2. Elegir la app **Helireport Desherbaje**
3. Menú izquierdo → **Testing → Internal testing**
4. Botón **Create new release**
5. Arrastrar el `.aab` de `dist/android/`
6. Escribir las notas de la versión en **Release notes**
7. **Next** → **Save** → **Review release**
8. **Start rollout to Internal testing** → confirmar

### 3. Comprobar

El testers ven la actualización en unos minutos. Estado en **Testing → Internal testing → Releases**.

Para pasar a producción: **Production → Create new release → Add from library** y elegir ese mismo build.

---

## Publicar en App Store / TestFlight

### 1. Construir

```bash
./scripts/build.sh ios --bump
```

Sale: `dist/ios/helireport_desherbaje-<version>+<build>.ipa`

Si falla con error de firma: abrir `ios/Runner.xcworkspace` en Xcode → target **Runner** → pestaña **Signing & Capabilities** → comprobar que el Team está seleccionado y que hay perfil válido. Volver a lanzar el script.

### 2. Subir

**Opción A — Transporter (recomendada):**

1. Abrir la app **Transporter** (gratis en Mac App Store)
2. Iniciar sesión con el Apple ID del equipo
3. Arrastrar el `.ipa` de `dist/ios/`
4. Botón **Deliver**
5. Esperar a que ponga "Delivered"

**Opción B — línea de comandos:**

```bash
xcrun altool --upload-app --type ios \
  --file dist/ios/helireport_desherbaje-<version>+<build>.ipa \
  --apiKey <ASC_KEY_ID> --apiIssuer <ASC_ISSUER_ID>
```

### 3. Comprobar

1. Abrir https://appstoreconnect.apple.com
2. **Apps → Helireport Desherbaje → TestFlight**
3. El build aparece en 5–15 min con estado "Processing"; luego pasa a "Ready to Test"
4. Si pide **Export Compliance**: responder que la app **usa cifrado estándar (HTTPS)** y está exenta
5. Añadir el build al grupo de testers

Para publicar en la App Store: **Distribution → + Version** → rellenar novedades → **Add Build** → **Submit for Review**.

---

## Las dos tiendas de una vez

```bash
./scripts/build.sh both --bump
```

Genera AAB e IPA con la **misma versión**. Luego seguir los pasos de subida de cada tienda.

---

## Versionado

`--bump` sube la versión sola. Regla: build number = `major*100 + minor*10 + patch`.

```
1.0.4+104  →  1.0.5+105
1.0.9+109  →  1.1.0+110
1.9.9+199  →  2.0.0+200
```

Ambas tiendas **rechazan un build number repetido**. Nunca subir dos artefactos con la misma versión.

Para saltar a una versión concreta: editar a mano `version:` en `pubspec.yaml` y construir **sin** `--bump`.

---

## Flags del script

```bash
./scripts/build.sh android          # AAB
./scripts/build.sh ios              # IPA
./scripts/build.sh both             # AAB + IPA

  --bump        sube la versión antes de construir
  --no-clean    omite flutter clean (más rápido, para repetir un build)
  --apk         genera además un APK para instalar a mano en un móvil
```

---

## Tras publicar

1. Commitear el cambio de versión:
   ```bash
   git add pubspec.yaml ios/Runner.xcodeproj/project.pbxproj
   git commit -m "chore: release 1.0.5+105"
   ```
2. Anotar la entrega en `docs/DEVLOG.md`.

---

## Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| El script aborta: "Falta .env con HMAC_SECRET" | No existe `.env` | Pedir el fichero al responsable y ponerlo en la raíz |
| La app instalada da error de login o "sin permisos" en todo | Build hecho sin `.env` | Reconstruir con el script; no usar `flutter build` a pelo |
| Google Play: "Version code already used" | Build number repetido | `./scripts/build.sh android --bump` y subir el nuevo |
| App Store: "The bundle version must be higher" | Igual que arriba | Igual que arriba |
| "No se generó IPA (revisa signing en Xcode)" | Certificado o perfil caducado | Xcode → Runner → Signing & Capabilities → renovar |
| "Falta android/key.properties" | Ordenador sin las claves de firma | Copiar `key.properties` y el `.jks` del responsable (no están en git) |
