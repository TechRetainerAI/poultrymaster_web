# PoultryMaster / PoultryCore

A multi-tenant SaaS for small businesses in Ghana. One codebase serves three
kinds of company — **Water** (sachet/bottled water production & delivery),
**Poultry** (flocks, eggs, feed), and **Generic** (products, sales, expenses).
A user can own several companies and switch between them; the active company's
type decides which menus and features show.

> **New here? Read this once, then jump to [Quick start](#-quick-start-easiest-way).**
> The fastest way to get running is **Option A** — start only the website and
> point it at the live development server. You do **not** need .NET or a database
> for that.

---

## 🧱 What's in this repo

| Folder | What it is | Tech |
|---|---|---|
| `./` (root) | The website (frontend) | **Next.js 16 / React 19**, TypeScript, Tailwind |
| `poultrycore/PoultryFarmAPI/` | Main business API (water/poultry/generic) | **.NET 8**, raw SQL + stored procedures |
| `poultrycore/LoginAPI/User.Management.API/` | Login, accounts, companies, payments | **.NET 8**, ASP.NET Identity |
| `poultrycore/PoultryFarmAPI/Migrations/` | Database scripts (run in number order) | SQL Server `.sql` files |

**How the pieces talk:** the browser only ever calls the website. The website
forwards API calls server-side to the two .NET APIs (this avoids CORS/login
issues). Which API gets the call is decided by the URL path — `Admin`,
`Authentication`, `Payments`, `UserProfile`, `Companies` go to the **Login API**;
everything else goes to the **Farm API**.

---

## ✅ Prerequisites

- **Node.js 20 LTS** (or newer) and npm — required for everything.
  Check with `node -v` (should be 20+).
- *(Only for Option B)* **.NET 8 SDK** and access to a **SQL Server** database.

---

## 🚀 Quick start (easiest way)

### Option A — Website only, against the live DEV backend  *(recommended)*

This runs just the website on your machine and uses our already-deployed
development API + database. Nothing else to install.

```bash
# 1. Install dependencies
npm install

# 2. Create your local env file from the ready-made template
#    (Windows PowerShell)
copy .env.local.example .env.local
#    (macOS / Linux / Git Bash)
cp .env.local.example .env.local

# 3. Start the dev server
npm run dev
```

Open **http://localhost:3000**. Log in with an account on the dev system
(ask the project owner for test credentials).

> If the dev server misbehaves with Turbopack, use the Webpack fallback:
> `npm run dev:webpack`

That's it for most debugging — you can see the UI, reproduce the error, edit
code, and the page hot-reloads.

---

### Option B — Full local stack (only if you're changing the .NET APIs)

You only need this if the bug is in the backend (C#) or database. Otherwise use
Option A.

**1. Database (SQL Server)**

You need a SQL Server instance (local, Docker, or the shared dev server — ask
the owner for the connection details). Apply the migrations in number order:

```bash
# from poultrycore/PoultryFarmAPI/Migrations, run each NNN_*.sql in order
sqlcmd -S <server> -U <user> -P <password> -d <database> -b -i 001_*.sql
# ... continue through the highest-numbered file
```

Migrations are idempotent (safe to re-run) and must be applied with a database
user that has DDL rights.

**2. Farm API** (`poultrycore/PoultryFarmAPI/`)

It needs two settings or it refuses to start:

```bash
cd poultrycore/PoultryFarmAPI
dotnet user-secrets init
dotnet user-secrets set "ConnectionStrings:PoultryConn" "Server=<server>;Database=<db>;User Id=<user>;Password=<pw>;TrustServerCertificate=True"
dotnet user-secrets set "JWT:Secret" "<a-long-random-string-at-least-32-characters>"
dotnet run
```

Runs at **https://localhost:7190** (or **http://localhost:5142**).

**3. Login API** (`poultrycore/LoginAPI/User.Management.API/`)

```bash
cd poultrycore/LoginAPI/User.Management.API
dotnet user-secrets set "JWT:Secret" "<the-SAME-string-you-used-for-the-Farm-API>"
# set its connection string the same way if required by appsettings
dotnet run
```

Runs at **https://localhost:7010** (or **http://localhost:5010**).

> ⚠️ **`JWT:Secret` must be the exact same value (≥32 characters) on both APIs**,
> or logins from one won't be accepted by the other.

**4. Point the website at your local APIs** — edit `.env.local`:

```
NEXT_PUBLIC_API_BASE_URL=localhost:7190
NEXT_PUBLIC_ADMIN_API_URL=localhost:7010
FARM_API_URL=https://localhost:7190
ADMIN_API_URL=https://localhost:7010
```

Then `npm run dev`.

---

## 🛠️ Useful commands

```bash
npm run dev          # start the website (hot reload)
npm run dev:webpack  # same, but Webpack instead of Turbopack (fallback)
npm run build        # production build — also catches most code errors
npx tsc --noEmit     # strict TypeScript type-check (build does NOT fail on type errors)
```

> Note: there is **no automated test suite**. `npm run lint` just runs the build.
> `next.config.mjs` ignores TypeScript errors during build, so run
> `npx tsc --noEmit` if you want real type checking.

---

## 🐞 Common errors & fixes

| Symptom | Likely cause / fix |
|---|---|
| `npm run dev` fails immediately | Node too old. Install **Node 20+** (`node -v`). |
| Login works but data pages are blank / 500 | `.env.local` not pointing at a working API. Re-copy `.env.local.example`. |
| `unauthorized` / instant logout | The two APIs have different `JWT:Secret` (Option B), or your token expired — log in again. |
| Backend won't start: *"Connection string 'PoultryConn' not found"* | Set it via `dotnet user-secrets` (Option B, step 2). |
| Backend won't start: *"JWT:Secret is not configured / too short"* | Set a 32+ char `JWT:Secret` on **both** APIs. |
| *"Could not find stored procedure …"* | The database is missing migrations — apply the `Migrations/*.sql` files in order. |
| Page styles look broken after pulling | `npm install` again (dependencies changed). |

---

## 📦 Where things live (frontend)

- `app/` — the pages (App Router). Water pages are `app/water-*`, generic are
  `app/generic-*`, poultry pages use names like `app/flocks`, `app/egg-production`.
- `components/ui/` — shared building blocks (buttons, tables, dialogs). Reuse
  these; don't fork them.
- `lib/api/` — functions that call the backend (`water.ts`, `generic.ts`, etc.).
- `lib/store/auth-store.ts` — who's logged in and which company is active.

For deeper architecture notes, see **CLAUDE.md** in the repo root.

---

## 🙋 Getting unblocked

If something here is out of date or a step doesn't work, tell the project owner
exactly which command you ran and the full error message — that's the fastest
way to get help.
