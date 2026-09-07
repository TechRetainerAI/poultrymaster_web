# PoultryMaster Mobile (Android)

Flutter client for the PoultryMaster / PoultryCore backend. Talks directly to the
two production Cloud Run APIs (no proxy needed on mobile):

- **Login API** — `https://usermanagementapi.poultrycore.com` (auth, JWT, 2FA)
- **Farm API** — `https://farmapi.poultrycore.com` (all farm data)

Override either at build time:

```bash
flutter run --dart-define=FARM_API=https://your-farm-api --dart-define=LOGIN_API=https://your-login-api
```

## Features

- **Auth**: sign in (with email-OTP 2FA when the account has it enabled),
  registration, forgot password, secure token storage
  (`flutter_secure_storage`), automatic refresh-token retry on 401.
- **Dashboard**: today's eggs / feed / sales / expenses, active flock count,
  egg-production trend chart, quick-add shortcuts.
- **Production**: egg production, feed usage, daily production records, flocks.
- **Finance**: sales, expenses, customers.
- **Farm setup** (More tab): flocks, batches, houses, inventory.
- All modules support create, edit (tap), delete (long-press), search, and
  pull-to-refresh.

## Architecture

```
lib/
  core/        config (API hosts), theme, Dio client + 401 refresh, JSON helpers
  models/      Session (login payload parsing)
  services/    AuthService (Login API), FarmService (generic Farm API CRUD)
  state/       AppState — auth status ChangeNotifier (provider)
  resources/   ResourceSpec + one spec per module: endpoint, id key, icon,
               list rendering, and form fields. Adding a CRUD module is
               ~30 lines in resources.dart — the list & form screens are generated.
  screens/     auth/, shell/ (bottom nav), dashboard/, hub/, resource/, more/
  widgets/     logo, stat cards, empty/error states
```

Field names come from the Farm API C# models (`PoultryFarmAPI/Models/*.cs`),
which differ from the stale Postman collection in places (e.g. Flock uses
`name`/`startDate`/`active`). JSON is parsed case-insensitively because the
backends mix camelCase and PascalCase.

## Design

- Fonts: **Sora** (headings) + **Plus Jakarta Sans** (body) via `google_fonts`.
- Icons: **Iconsax** (`iconsax_flutter`) + a generated adaptive launcher icon
  (green field, amber egg — regenerate with `dart run flutter_launcher_icons`
  after editing `assets/icon/`).
- Palette: forest green `#1E6B3C`, egg-yolk amber `#F2A93B`, warm cream surface.

## Build

```bash
flutter pub get
flutter run                 # on a connected device/emulator
flutter build apk --release # release APK
```
