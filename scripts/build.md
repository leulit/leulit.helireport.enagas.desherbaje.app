# build.sh — Guía de uso

Script de construcción de artefactos de release para **Helireport Desherbaje** (Android y iOS).

---

## Uso

> Manual de publicación paso a paso: [`docs/PUBLICAR.md`](../docs/PUBLICAR.md). Este fichero documenta el script.

```bash
./scripts/build.sh android          # AAB para Google Play
./scripts/build.sh ios              # IPA para App Store / TestFlight
./scripts/build.sh both             # AAB + IPA
```

### Flags opcionales

| Flag | Efecto |
|---|---|
| `--bump` | Sube `version:` de `pubspec.yaml` (regla odómetro, ver `bump-version.sh`) antes de construir. |
| `--no-clean` | Omite `flutter clean`. Más rápido; útil para builds incrementales. |
| `--apk` | (solo `android`/`both`) Genera también un APK universal además del AAB. |
| `--upload` | (solo `ios`/`both`) Sube el IPA a App Store Connect con `xcrun altool` al terminar. Lee `ASC_KEY_ID`/`ASC_ISSUER_ID` del entorno o de `.asc.env` (gitignored), y exige `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`. |

---

## Prerrequisitos

| Requisito | Android | iOS |
|---|---|---|
| `flutter` en PATH | ✅ | ✅ |
| `.env` con `HMAC_SECRET` en la raíz | ✅ | ✅ |
| `android/key.properties` | ✅ | — |
| `android/helireport-desherbaje-release.jks` | ✅ | — |
| macOS + Xcode (`xcodebuild`) | — | ✅ |
| CocoaPods (`pod`) | — | ✅ |

---

## Flujo interno

```
1. Parseo de args y validación de target (android | ios | both)
2. Validación de .env (HMAC_SECRET) → DEFINES=(--dart-define-from-file=.env)
2b. --bump (opcional) → bump-version.sh
3. Lectura de versión desde pubspec.yaml  →  VERSION_NAME + BUILD_NUMBER
3b. release-notes.sh → borrador de "Novedades" de la versión
3. flutter clean   (omitible con --no-clean)
4. flutter pub get
5. build_android() y/o build_ios()        (según target)
6. Resumen de pasos para subir a tiendas
7. Apertura de Finder en dist/            (solo macOS)
```

### build_android()

1. Comprueba que existen `key.properties` y el keystore `.jks`.
2. Ejecuta `flutter build appbundle --release --dart-define-from-file=.env`. Sin ese define, `AppConfig.hmacSecret` sale con el placeholder y el backend devuelve 401 en toda la API.
3. Copia el AAB a `dist/android/helireport_desherbaje-<version>+<build>.aab`.
4. Si `--apk`: ejecuta `flutter build apk --release` y copia el APK al mismo directorio.

### build_ios()

1. Requiere macOS; aborta en Linux/Windows.
2. Ejecuta `pod install --repo-update` dentro de `ios/`.
3. Ejecuta `flutter build ipa --release --export-method app-store --dart-define-from-file=.env`.
4. Copia el IPA a `dist/ios/helireport_desherbaje-<version>+<build>.ipa`.
5. Si `--upload`: `xcrun altool --upload-app`. Si falla, el IPA queda en `dist/` para subirlo con Transporter.

---

## Artefactos generados

```
dist/
├── android/
│   ├── helireport_desherbaje-<version>+<build>.aab    # siempre
│   └── helireport_desherbaje-<version>+<build>.apk    # solo con --apk
└── ios/
    └── helireport_desherbaje-<version>+<build>.ipa
```

---

## Publicación tras el build

### Google Play

1. [Google Play Console](https://play.google.com/console) → Helireport Desherbaje
2. **Testing → Internal testing** (o el track que toque) → **Create new release**
3. Sube el archivo `.aab` de `dist/android/`
4. **Review release → Start rollout**

### App Store / TestFlight

**Opción A — gráfica:** abre **Transporter** (Mac App Store) y arrastra el `.ipa`.

**Opción B — CLI:**

```bash
xcrun altool --upload-app --type ios \
  --file dist/ios/helireport_desherbaje-<version>+<build>.ipa \
  --apiKey <ASC_KEY_ID> --apiIssuer <ASC_ISSUER_ID>
```

El build aparece en TestFlight → Internal Testing tras ~5-15 min.

---

## Versionado

La versión se lee automáticamente de `pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^^^^^ ^^^
#        name  build number
```

Usa `--bump` para incrementarla automáticamente antes de cada build destinado a las tiendas. Ambas tiendas rechazan un build number repetido.

---

## Novedades de la versión (What's New)

Cada build genera el borrador del texto de novedades en:

```
store_assets/texts/whatsnew/es-ES_<version>.txt
```

Lo produce `release-notes.sh`, que recoge los commits **Conventional Commits** `feat:` y `fix:` posteriores al último cambio de la línea `version:` en `pubspec.yaml` (no hay tags de release, así que ese es el corte).

```bash
./scripts/release-notes.sh            # versión actual de pubspec.yaml
./scripts/release-notes.sh 1.2.0      # versión explícita
./scripts/release-notes.sh --force    # regenera pisando el fichero existente
```

- **Idempotente**: si el fichero de esa versión ya existe, no lo pisa. Así el texto que redactes a mano sobrevive a los rebuilds.
- **Es un borrador**: los subjects son técnicos y en inglés. Reescríbelos en lenguaje de operador antes de publicar.
- **Límites**: App Store admite 4000 caracteres; Google Play corta en **500**. El script avisa si se pasa de 500, para que el mismo texto sirva en ambas tiendas.
- Commits que no empiezan por `feat:`/`fix:` (chore, docs, test, refactor…) se ignoran: no son visibles para el operador.

Destino del texto:
- App Store Connect → versión → **Novedades de esta versión**
- Play Console → release → **Notas de la versión**
