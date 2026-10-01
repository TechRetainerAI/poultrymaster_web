# PoultryCore Mobile

Flutter client for the PoultryCore / VisibilityCore platform. Talks to the same
two services as the web app — no mobile-specific backend.

## What this build is

A **thin shell across all five company types**: sign in, pick a company, and see
that company's dashboard figures. Deep module screens are not built yet; the
dashboard lists each type's modules marked "Soon".

The point of shipping this first is that it proves the three things every later
screen depends on: authentication (including 2FA), company switching, and
company-type gating.

## Running it

```bash
flutter pub get
flutter run                                     # dev APIs (default)
flutter run --dart-define=POULTRYCORE_ENV=prod  # production APIs
```

The environment is a compile-time constant, and the app shows a banner naming
it on every screen. On the web there is an address bar to check; on a phone
there is nothing, so the app says which backend it is on out loud. The default
is **dev** so a debug build cannot write to customer records.

| | dev | prod |
|---|---|---|
| Login API | `poultrymaster-login-api-dev` | `poultrymaster-api-git` |
| Farm API | `poultrymaster-farm-api-dev` | `poultrymaster-farm-api-git` |

## How it talks to the API

Three behaviours exist because the backend requires them:

**Responses are PascalCase, inconsistently.** `/Companies/mine` answers in
PascalCase; most farm endpoints answer in camelCase. `ApiClient.normalise`
lowercases the first letter of every key recursively, so every model in this app
reads camelCase. The web client does the same thing for the same reason.

**Access tokens last 60 minutes.** A 401 mid-session is routine, not a login
failure. `ApiClient` refreshes once and replays the request before surfacing an
error; only if the refresh fails is the user returned to the login screen.

**Switching company is a server call, not a client selection.**
`POST /api/Companies/switch` mints a *new* access token carrying the farm claim.
The new token must replace the stored one, or every later call still reads the
previous company's data.

## Company types

`Farms.Type` is one of Poultry, Water, Generic, Restaurant, Hotel. It decides
which modules exist and which endpoints will answer — calling a module for the
wrong type returns **409 Conflict**, which the dashboard reports as "this
company type does not expose that module" rather than as a raw error.

An unrecognised type degrades to an explanatory card instead of crashing,
because new company types have shipped to the platform before this app knew
about them.

## Dashboard endpoints

There is no single dashboard API — each module grew its own, with different
shapes and different casing for the same parameter:

| Type | Endpoint | Note |
|---|---|---|
| Poultry | `/api/poultry/reports/farm-summary` | takes `FarmId` — capital F, unlike every other module |
| Water | `/api/Water/dashboard/summary` | |
| Hotel | `/api/Hotel/dashboard/summary` | |
| Generic | `/api/generic-company/{farmId}/reports/dashboard` | farmId in the path |
| Restaurant | `/api/Restaurant/reports/daily-sales` | no dashboard endpoint exists; today's sales stands in, and the UI says so |

Most of these declare only `200 Success` in swagger with no response schema, so
`DashboardApi` surfaces whatever scalar fields come back rather than hard-coding
a model per module that would break the first time a field is renamed.

## Tests

```bash
flutter test
```

Covers the normalisation pass and company-type parsing — the two pieces of
logic where a silent mistake would show wrong data rather than fail loudly.

## What comes next

Deep screens per module, starting with whichever the business needs on phones
first. The API surface is 945 paths / 1312 operations, so the modules are worth
building one at a time against real use, not generated wholesale.
