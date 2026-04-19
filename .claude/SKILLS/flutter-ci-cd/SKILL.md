---
name: flutter-ci-cd
description: >
  Flutter CI/CD skill — use this whenever the project involves continuous
  integration, continuous deployment, automated builds, GitHub Actions,
  Fastlane, app store publishing, Play Store publishing, Firebase App
  Distribution, build automation, environment configuration, or any pipeline
  setup. Triggers on mentions of CI/CD, pipeline, GitHub Actions, Fastlane,
  build, deploy, publish, Play Store, App Store, Firebase distribution,
  automated release, or environment variables in build context.
  Always apply alongside flutter-core.
---

# Flutter CI/CD Skill

> Always apply **flutter-core** in parallel. This skill extends it for CI/CD.

## Stack

| Tool | Purpose |
|---|---|
| **GitHub Actions** | CI runner — free for public repos, cost-effective for private |
| **Fastlane** | iOS/Android distribution automation |
| **Firebase App Distribution** | Beta distribution to testers |
| **`--dart-define`** | Environment variables at build time |

---

## Repository Structure

```
.github/
└── workflows/
    ├── ci.yml           # Run on every PR: test + analyze
    ├── build-web.yml    # Build and deploy web
    ├── build-android.yml # Build APK/AAB
    └── build-ios.yml    # Build IPA (macOS runner)
fastlane/
├── Fastfile
├── Appfile
└── Pluginfile
```

---

## Workflow 1: CI on Pull Requests

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop]

jobs:
  analyze-and-test:
    name: Analyze & Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable
          cache: true # Cache Flutter SDK

      - name: Cache pub dependencies
        uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: ${{ runner.os }}-pub-${{ hashFiles('**/pubspec.lock') }}
          restore-keys: ${{ runner.os }}-pub-

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Format check
        run: dart format --set-exit-if-changed .

      - name: Run tests
        run: flutter test --coverage --reporter expanded

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          file: coverage/lcov.info
          token: ${{ secrets.CODECOV_TOKEN }}
```

---

## Workflow 2: Build Flutter Web → Deploy

```yaml
# .github/workflows/build-web.yml
name: Build & Deploy Web

on:
  push:
    branches: [main]

jobs:
  build-web:
    name: Build Web
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable
          cache: true

      - run: flutter pub get

      - name: Build Web (CanvasKit)
        run: |
          flutter build web \
            --web-renderer canvaskit \
            --tree-shake-icons \
            --release \
            --dart-define=API_BASE_URL=${{ secrets.API_BASE_URL_PROD }} \
            --dart-define=ENVIRONMENT=production

      - name: Deploy to Firebase Hosting
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: ${{ secrets.GITHUB_TOKEN }}
          firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          channelId: live
          projectId: your-firebase-project-id
```

---

## Workflow 3: Build Android

```yaml
# .github/workflows/build-android.yml
name: Build Android

on:
  push:
    branches: [main]
  workflow_dispatch: # Manual trigger

jobs:
  build-android:
    name: Build Android AAB
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable
          cache: true

      - run: flutter pub get

      # Decode keystore from base64 secret
      - name: Decode Keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/release.jks

      - name: Build AAB
        run: |
          flutter build appbundle \
            --release \
            --dart-define=API_BASE_URL=${{ secrets.API_BASE_URL_PROD }} \
            --dart-define=ENVIRONMENT=production
        env:
          KEY_STORE_PATH: release.jks
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
          STORE_PASSWORD: ${{ secrets.STORE_PASSWORD }}

      - name: Upload AAB artifact
        uses: actions/upload-artifact@v4
        with:
          name: release-aab
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 7

      - name: Distribute to Firebase App Distribution
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_ANDROID_APP_ID }}
          serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          groups: testers
          file: build/app/outputs/bundle/release/app-release.aab
```

---

## Workflow 4: Build iOS

```yaml
# .github/workflows/build-ios.yml
name: Build iOS

on:
  workflow_dispatch:
  push:
    branches: [main]

jobs:
  build-ios:
    name: Build iOS IPA
    runs-on: macos-latest # Required for iOS builds
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable
          cache: true

      - run: flutter pub get

      - name: Install Apple certificates
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.IOS_DISTRIBUTION_CERT_BASE64 }}
          p12-password: ${{ secrets.IOS_DISTRIBUTION_CERT_PASSWORD }}

      - name: Install provisioning profile
        run: |
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          echo "${{ secrets.IOS_PROVISION_PROFILE_BASE64 }}" | \
            base64 --decode > ~/Library/MobileDevice/Provisioning\ Profiles/profile.mobileprovision

      - name: Build iOS
        run: |
          flutter build ios \
            --release \
            --no-codesign \
            --dart-define=API_BASE_URL=${{ secrets.API_BASE_URL_PROD }}

      - name: Build IPA with Fastlane
        run: fastlane ios build_ipa
        env:
          FASTLANE_SKIP_UPDATE_CHECK: true
```

---

## Android Signing Configuration

```groovy
// android/app/build.gradle
android {
    signingConfigs {
        release {
            storeFile file(System.getenv("KEY_STORE_PATH") ?: "debug.keystore")
            storePassword System.getenv("STORE_PASSWORD") ?: "android"
            keyAlias System.getenv("KEY_ALIAS") ?: "androiddebugkey"
            keyPassword System.getenv("KEY_PASSWORD") ?: "android"
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
        }
    }
}
```

```bash
# Generate keystore (do once, store securely)
keytool -genkey -v \
  -keystore release.jks \
  -alias your-key-alias \
  -keyalg RSA -keysize 2048 \
  -validity 10000

# Encode for GitHub secret
base64 -i release.jks | pbcopy  # macOS
```

---

## Environment Variables per Target

```bash
# Development
flutter run \
  --dart-define=API_BASE_URL=https://api.dev.example.com \
  --dart-define=ENVIRONMENT=development

# Staging
flutter build apk \
  --dart-define=API_BASE_URL=https://api.staging.example.com \
  --dart-define=ENVIRONMENT=staging

# Production
flutter build appbundle \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=ENVIRONMENT=production
```

```dart
// Access in code — type-safe, no runtime lookup
class Env {
  static const apiUrl = String.fromEnvironment('API_BASE_URL');
  static const environment = String.fromEnvironment('ENVIRONMENT',
      defaultValue: 'development');
  static bool get isProduction => environment == 'production';
}
```

---

## Fastlane Setup (iOS + Android)

```ruby
# fastlane/Fastfile
default_platform(:ios)

platform :ios do
  desc "Build and distribute to TestFlight"
  lane :beta do
    build_app(
      scheme: "Runner",
      export_method: "app-store",
      output_directory: "build/ios",
    )
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end

platform :android do
  desc "Build and distribute to Play Store internal track"
  lane :internal do
    gradle(
      task: "bundle",
      build_type: "Release",
      project_dir: "android/",
    )
    upload_to_play_store(
      track: "internal",
      aab: "build/app/outputs/bundle/release/app-release.aab",
    )
  end
end
```

---

## GitHub Secrets Checklist

Set these in **Settings → Secrets and variables → Actions**:

| Secret | Description |
|---|---|
| `API_BASE_URL_PROD` | Production API endpoint |
| `KEYSTORE_BASE64` | Android keystore as base64 |
| `KEY_ALIAS` | Keystore key alias |
| `KEY_PASSWORD` | Key password |
| `STORE_PASSWORD` | Keystore password |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase service account JSON |
| `FIREBASE_ANDROID_APP_ID` | Firebase Android app ID |
| `IOS_DISTRIBUTION_CERT_BASE64` | Apple distribution cert as base64 |
| `IOS_DISTRIBUTION_CERT_PASSWORD` | Cert password |
| `IOS_PROVISION_PROFILE_BASE64` | Provisioning profile as base64 |
| `CODECOV_TOKEN` | Codecov upload token |

---

## Reference Files

- `references/play-store-publishing.md` — Play Console setup, track promotion, release notes automation
- `references/app-store-publishing.md` — App Store Connect, TestFlight, metadata automation with Fastlane Deliver
