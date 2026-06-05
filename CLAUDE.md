# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This repo holds **both** the frontend and the backend services.

- Root (`./`) — Next.js 16 / React 19 frontend (App Router, TypeScript, Tailwind 4, Radix-based `components/ui/`). This is the only Node project.
- `poultrycore/PoultryFarmAPI/` — .NET 8 Web API. The main business backend (poultry, water, and generic-company modules). Uses raw ADO.NET + SQL Server stored procedures, **not** EF Core.
- `poultrycore/LoginAPI/User.Management.API/` — .NET 8 Web API. Auth/JWT, multi-company ownership (`/api/Companies/*`), and Paystack payments/subscriptions (`/api/Payments/*`). Uses ASP.NET Identity + EF Core for user tables only; companies use raw SQL in `User.Management.Data/`.
- `poultrycore/PoultryWeb/` — legacy ASP.NET MVC site (largely superseded by the Next.js app; touch only when explicitly asked).
- `poultrycore/PoultryFarmAPI/Migrations/NNN_*.sql` — the **canonical** SQL migration set (numerical order, idempotent). See "Database" below.

## Common commands

### Frontend (run from repo root)

```bash
npm run dev          # Next.js dev server (Turbopack)
npm run dev:webpack  # fallback if Turbopack misbehaves
npm run build        # production build (also aliased as `verify` and `lint`)
npm start            # runs the standalone server via server.js (IISNode-compatible)
```

There is **no test runner configured** — `npm run lint` is just `next build`. Playwright is installed for `npm run screenshots` only. Don't claim tests pass; there aren't any.

Note: `next.config.mjs` sets `typescript.ignoreBuildErrors: true`, so `next build` will **not** catch TS errors. Run `npx tsc --noEmit` if you need real type checking.

### Backend (.NET, run from each project directory)

```bash
dotnet run                           # local dev
dotnet build
dotnet publish -c Release            # used by the Dockerfiles
```

`PoultryFarmAPI` requires `ConnectionStrings__PoultryConn` and `JWT__Secret` (≥32 chars, **same value** as Login API) or it throws on startup — see `poultrycore/PoultryFarmAPI/Program.cs:29-50`.

### Deployment

- Frontend → Cloud Run service `poultrymaster-web` (container port **8080**). Built from root `Dockerfile`. `NEXT_PUBLIC_*` vars are inlined at build time — set them in `.env.production` or via `--build-arg`; **runtime env vars alone won't reach the client bundle** (`Dockerfile:25-43`).
- Farm API → `poultrycore/cloudbuild.farm.yaml` (or root `poultrycore/cloudbuild.yaml`, kept in sync) → Cloud Run `poultrymaster-farm-api-git` (prod) / `poultrymaster-farm-api-dev` (dev).
- Login API → `poultrycore/cloudbuild.login.yaml` → Cloud Run `poultrymaster-api-git`. Keep separate triggers; otherwise one service stays on a stale image.

## Architecture

### Three company types, one codebase

A user (admin) can own multiple "farms" (companies). Each has a `Type`: **`Poultry`**, **`Water`**, or **`Generic`**. The active farm's type drives which navigation/modules the sidebar shows (`components/dashboard/sidebar.tsx` keys off `useAuthStore().activeFarmType`). Companies and the switching logic live in the Login API; the active farm id is sent on every Farm API request.

When adding a feature, decide which type it belongs to first — there are dedicated route prefixes:

- Poultry: `/flocks`, `/houses`, `/egg-production`, `/feed-usage`, `/health`, `/inventory`, etc.
- Water: `/water-*` (16+ routes — production, distribution, raw materials, finance, payroll, maintenance).
- Generic: `/generic-*` (products, sales, purchases, expenses, cash, daily closing, reports).

### Same-origin proxy (browser → Next → backends)

The browser **never** talks to the .NET APIs directly. All client requests go to same-origin `/api/proxy/*`, which `app/api/proxy/[...path]/route.ts` forwards server-side. The proxy decides which backend by inspecting the first path segment:

- `Admin`, `Authentication`, `Payments`, `UserProfile`, `Companies` → **Login API** (`ADMIN_API_URL` / `NEXT_PUBLIC_ADMIN_API_URL`)
- Everything else → **Farm API** (`FARM_API_URL` / `NEXT_PUBLIC_API_BASE_URL`)

Defaults when env is unset come from `lib/api/default-api-hosts.ts` and point at **production** Cloud Run URLs — so an unconfigured local dev silently hits prod. Always set `.env.local` before running locally.

`lib/api/config.ts` (`buildApiUrl`, `farmApiUrl`, `loginApiUrl`) is the single place that builds URLs — it strips/adds `/api/` correctly for proxy vs direct mode. Use these helpers; never hand-build URLs.

### Auth & state

- `lib/api/client.ts` is an axios singleton with a 401-refresh interceptor and a refresh queue (Farm API only — the proxy paths use `fetch` directly via the helpers above). Token lives in `localStorage.auth_token` and is mirrored into the axios instance on boot.
- `lib/store/auth-store.ts` (Zustand + `persist` under key `auth-storage`) holds `token`, `user`, `companies`, and `activeFarmId/Name/Type`. When changing active company you call `setActiveCompany(...)` which **also** writes `farmId`/`farmName`/`farmType` to `localStorage` so non-React code (`getUserContext()` in `lib/api/config.ts`) can read them.
- React Query is wired in `components/providers/query-provider.tsx` (mounted in `app/layout.tsx`). Server-state caching belongs here, not in Zustand.
- `components/auth/subscription-guard.tsx` currently has `TEMP_ALLOW_ALL_ACCESS = true` — flip with care.

### Backend service shape (Farm API)

`poultrycore/PoultryFarmAPI/Program.cs` registers ~60 scoped services, all constructed with the connection string. Each `XxxService.cs` in `Business/` is a thin wrapper around `SqlConnection` + `EXEC spXxx_*`. There is no repository/EF layer — **every read and write goes through a stored procedure**. To add an endpoint:

1. Write the SP in a new migration file `NNN_Description.sql` (next number in sequence).
2. Add a service interface + class in `PoultryFarmAPI/Business/` that calls the SP.
3. Register it in `Program.cs`.
4. Add a controller in `Controllers/` (the `AuditLogActionFilter` is applied globally, so writes auto-audit).
5. Add a frontend wrapper in `lib/api/<feature>.ts` using `farmApiUrl` + `getAuthHeaders`.

`GlobalExceptionMiddleware` turns `SqlException` into JSON with the SQL error number/message — so a missing SP surfaces as a readable 500, not an HTML page.

## Database

- SQL Server. Dev DB: `PoultryMasterDev`. Prod DB: `PoultryMaster`. Connect string lives in `appsettings.*.json` / `ConnectionStrings__PoultryConn` env.
- Migrations are **plain `.sql` files in `poultrycore/PoultryFarmAPI/Migrations/`, run in numerical order**. They are written to be idempotent (each checks `sys.procedures` / column metadata before altering). Apply with `sqlcmd -b -i NNN_*.sql` as a `db_owner` or `db_ddladmin` login — the app login won't have DDL rights.
- **Prod skips 025+** (multi-company, water, generic). See `database/schema-sync/RUNBOOK.md` for the exact prod-vs-dev divergence and the procedure for catching prod up to a poultry-only subset.
- Beware: `Farms.Id` is the real PK. There's a vestigial `Farms.FarmId` column — commit `b4c3d22` switched `spCompany_*` to use `Id`. When writing new SPs, **always join on `Farms.Id`**.
- Backend JSON is PascalCase; `lib/api/companies.ts` has a `lower()` helper that recursively lowercases the first char so the TS layer can use camelCase. New API modules should do the same or define DTOs that match.

## Conventions worth knowing

- Path alias `@/*` → repo root (see `tsconfig.json`). Use it everywhere — relative `../../..` imports are not the house style.
- Shadcn-style UI primitives live in `components/ui/`. Compose them; don't fork. Feature components go in `components/<feature>/`.
- Permissions: staff vs admin gating is in `hooks/use-permissions.ts`. Staff are **deny-by-default** (`STAFF_FEATURE_BASE`); admins default-allow. Always gate nav and write actions with `usePermissions()` rather than re-reading localStorage.
- The CORS allow-list on the Farm API (`poultrycore/PoultryFarmAPI/Program.cs:251-328`) accepts `*.ngrok-*`, `poultrymaster.com`, `techretainer.com`, and the `farm-registry-portal` Cloud Run service. If you add a new frontend host, add it there or it will be blocked.
- The folder `poultrycore/PoultryFarmAPI/Migrations/ompal/` holds the long-form product specs ("Plan Mode" / "Main PROMPT" text files) for the Water and Generic Company modules. Skim the relevant one before designing a new module in that area.
