# slk-mobile

The Sree Lakshmi Kalamkari inventory & billing app for the floor and warehouse —
Flutter, native iOS + Android, full feature parity with the web app.

Part of the **L2S** workspace (`D:\e-commerce`). SLK-owned. It holds no stock of
its own: it reads and writes through the API, which is the single home for stock.

- Repo: <https://github.com/VVISTECH-git/slk-mobile> (branch `main`)
- Working copy: `D:\e-commerce\slk-mobile`

## Naming — read this before "fixing" anything

The repo and folder are **`slk-mobile`** (hyphen). Several identifiers inside the
project are **`slk_mobile`** (underscore) and must stay that way:

| Where | Value | Why it cannot change |
|---|---|---|
| `pubspec.yaml` → `name` | `slk_mobile` | Dart package names must be snake_case; hyphens are invalid. Every `import 'package:slk_mobile/…'` follows it. |
| `android/app/build.gradle.kts` → `applicationId` | `com.vvistech.slk_mobile` | This is the app's identity on Google Play. Changing it creates a *different* app and breaks updates for existing installs. |
| `android/app/build.gradle.kts` → `namespace`, `MainActivity.kt` → `package` | `com.vvistech.slk_mobile` | Kotlin package, tied to the source directory layout. |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.vvistech.slkMobile` | Registered bundle id; App Store Connect app `6797014476`. |

The rename from `slk_mobile` to `slk-mobile` was a **repo and folder** rename
only (2026-09-02). GitHub still redirects the old URL, but the hyphen form is
canonical.

## Running it

```bash
flutter pub get
flutter run
```

API base URL is resolved in [`lib/core/config.dart`](lib/core/config.dart):

- **release / profile** → `https://tantu-store.vercel.app` (production)
- **debug** → `http://10.0.2.2:3000` (the host machine's local tantu dev server, which
  runs against the dev database)

Debug builds can therefore never accidentally hit production. Override for any
build:

```bash
flutter run --dart-define=API_BASE_URL=https://tantu-store.vercel.app
```

`10.0.2.2` is the Android emulator's alias for the host's localhost. Use
`http://127.0.0.1:3000` on the iOS simulator, or your machine's LAN IP on a
physical device. All endpoints live under `/api/v1`.

## Stack

Riverpod (state) · go_router (routing) · Dio (networking) ·
flutter_secure_storage (tokens) · mobile_scanner (QR/barcode) · pdf + printing
(labels and invoices). Flutter SDK `^3.11.1`.

## Builds and releases

CI/CD is Codemagic — see [`codemagic.yaml`](codemagic.yaml), which has an
Android workflow (signed APK + AAB → Play) and an iOS workflow (signed IPA →
TestFlight). Neither workflow references the repo name, so the rename needs no
change there; only the Codemagic app's GitHub connection should be confirmed in
the UI.

iOS code signing is the fiddly part and is written up in
[`docs/ios-signing.md`](docs/ios-signing.md). Store listing copy and screenshots
live in [`store/`](store).

Current status: iOS on TestFlight; Android on Play internal testing (Android is
not going public — iOS is the real target).

## Layout

```
lib/
  core/        config, api_client, storage, providers, format
  models/      shared data models
  theme/       colours and typography
  widgets/     shared widgets
  features/    one folder per module — auth, home, category (labelled "Design"
               in the UI), products, pieces, pos, invoices, stock, transfers,
               production, dashboard, reports, settings
tool/          icon, splash and store-asset generators (run with dart run)
integration_test/   end-to-end flows and screenshot capture
store/         App Store / Play listing assets and copy
docs/          ios-signing.md
```

Regenerable and not in git: `build/`, `.dart_tool/`. `flutter pub get` restores
what you need.
