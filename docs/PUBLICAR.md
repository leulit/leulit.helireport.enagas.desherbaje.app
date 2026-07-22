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
| `.asc.env` + clave `.p8` (solo para `--upload`) | ver "Subida automática a TestFlight" |

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

Los testers ven la actualización en unos minutos. Estado en **Testing → Internal testing → Releases**.

Para pasar a producción: **Production → Create new release → Add from library** y elegir ese mismo build.

---

## Publicar en App Store / TestFlight

### 1. Construir y subir en un solo comando

```bash
./scripts/build.sh ios --bump --upload
```

Construye el IPA y lo sube a App Store Connect. Requiere las credenciales configuradas una vez (sección siguiente).

Sin `--upload`, el IPA queda en `dist/ios/helireport_desherbaje-<version>+<build>.ipa` y se sube a mano:

- **Transporter:** abrir la app (gratis en Mac App Store) → arrastrar el `.ipa` → **Deliver**.
- **Línea de comandos:**
  ```bash
  xcrun altool --upload-app --type ios \
    --file dist/ios/helireport_desherbaje-<version>+<build>.ipa \
    --apiKey RQK225Y9Q5 --apiIssuer af96dab8-e389-4d87-ab15-64346a5340cb
  ```

Si el build falla con error de firma: abrir `ios/Runner.xcworkspace` en Xcode → target **Runner** → **Signing & Capabilities** → comprobar Team y perfil. Volver a lanzar el script.

### 2. Comprobar

1. Abrir https://appstoreconnect.apple.com
2. **Apps → Helireport Desherbaje → TestFlight**
3. El build aparece en 5–15 min como "Processing"; luego pasa a "Ready to Test"
4. Si pide **Export Compliance**: la app usa cifrado estándar (HTTPS) y está exenta
5. Añadir el build al grupo de testers

Para publicar en la App Store: **Distribution → + Version** → rellenar novedades → **Add Build** → **Submit for Review**.

---

## Subida automática a TestFlight (configurar una vez por ordenador)

1. https://appstoreconnect.apple.com → **Users and Access → Integrations → App Store Connect API**
2. **+** → nombre, acceso **App Manager** → **Generate**
3. Apuntar el **KEY ID** (columna de la tabla) y el **Issuer ID** (encima de la tabla)
4. **Download API Key** — el `.p8` solo se descarga una vez:
   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
   ```
5. Crear `.asc.env` en la raíz del proyecto (gitignorado):
   ```
   ASC_KEY_ID=<KEY_ID>
   ASC_ISSUER_ID=<ISSUER_ID>
   ```
6. Comprobar que la credencial vale:
   ```bash
   xcrun altool --list-providers --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
   ```

El `.p8` es una credencial de la cuenta de desarrollador: nunca al repo. Si se filtra, revocarla en la misma pantalla de Integrations.

---

## Las dos tiendas de una vez

```bash
./scripts/build.sh both --bump --upload
```

Genera AAB e IPA con la **misma versión**, sube el IPA a TestFlight y deja el AAB en `dist/android/` para subirlo a Play Console a mano.

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
  --upload      (solo ios/both) sube el IPA a TestFlight al terminar
```

---

## Tras publicar

1. Commitear el cambio de versión:
   ```bash
   git add pubspec.yaml ios/Runner.xcodeproj/project.pbxproj
   git commit -m "chore: release 1.0.6+106"
   ```

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
| "--upload necesita ASC_KEY_ID y ASC_ISSUER_ID" | Falta `.asc.env` | Ver "Subida automática a TestFlight" |
| "Falta ~/.appstoreconnect/private_keys/AuthKey_*.p8" | La clave no está donde `altool` la busca | `mv AuthKey_*.p8 ~/.appstoreconnect/private_keys/` |
| `zsh: parse error near '\n'` al copiar un comando | Se dejaron los `<PLACEHOLDER>` literales | Sustituirlos por los valores reales, sin `<>` |
