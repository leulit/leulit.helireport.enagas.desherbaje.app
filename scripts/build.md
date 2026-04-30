# build.sh — Guía de uso

Script de construcción de artefactos de release para **Helireport Desherbaje** (Android y iOS).

---

## Uso

```bash
./scripts/build.sh android          # AAB para Google Play
./scripts/build.sh ios              # IPA para App Store / TestFlight
./scripts/build.sh both             # AAB + IPA
```

### Flags opcionales

| Flag | Efecto |
|---|---|
| `--no-clean` | Omite `flutter clean`. Más rápido; útil para builds incrementales. |
| `--apk` | (solo `android`/`both`) Genera también un APK universal además del AAB. |

---

## Prerrequisitos

| Requisito | Android | iOS |
|---|---|---|
| `flutter` en PATH | ✅ | ✅ |
| `android/key.properties` | ✅ | — |
| `android/helireport-desherbaje-release.jks` | ✅ | — |
| macOS + Xcode (`xcodebuild`) | — | ✅ |
| CocoaPods (`pod`) | — | ✅ |

---

## Flujo interno

```
1. Parseo de args y validación de target (android | ios | both)
2. Lectura de versión desde pubspec.yaml  →  VERSION_NAME + BUILD_NUMBER
3. flutter clean   (omitible con --no-clean)
4. flutter pub get
5. build_android() y/o build_ios()        (según target)
6. Resumen de pasos para subir a tiendas
7. Apertura de Finder en dist/            (solo macOS)
```

### build_android()

1. Comprueba que existen `key.properties` y el keystore `.jks`.
2. Ejecuta `flutter build appbundle --release`.
3. Copia el AAB a `dist/android/helireport_desherbaje-<version>+<build>.aab`.
4. Si `--apk`: ejecuta `flutter build apk --release` y copia el APK al mismo directorio.

### build_ios()

1. Requiere macOS; aborta en Linux/Windows.
2. Ejecuta `pod install --repo-update` dentro de `ios/`.
3. Ejecuta `flutter build ipa --release --export-method app-store`.
4. Copia el IPA a `dist/ios/helireport_desherbaje-<version>+<build>.ipa`.

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

Recuerda incrementar `version:` en `pubspec.yaml` antes de cada build destinado a las tiendas.
