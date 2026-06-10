# PoultryMaster — Complete Setup Guide (from a blank computer)

This guide takes you from **nothing installed** to **running the app**. Follow it
top to bottom. If you only need to fix something in the website (the UI), you can
stop after **Part 3 (Option A)** — you will not need .NET or a database.

- **Part 1** — Install the tools
- **Part 2** — Get the code
- **Part 3 — Option A** — Run the website only (easiest, recommended)
- **Part 4 — Option B** — Run everything locally (website + 2 APIs + database)
- **Part 5** — Everyday commands
- **Part 6** — Fixing common errors
- **Part 7** — How the project is organised
- **Part 8** — (Optional) Deploying

Commands are shown for **Windows (PowerShell)** first, then **macOS / Linux**
where they differ.

---

## Part 1 — Install the tools

### 1.1 Required for EVERYTHING

| Tool | Why | Get it | Check it works |
|---|---|---|---|
| **Git** | download the code | https://git-scm.com/downloads | `git --version` |
| **Node.js 20 LTS** (incl. npm) | runs the website | https://nodejs.org (pick **LTS**) | `node -v` → should say `v20` or higher, and `npm -v` |
| **VS Code** (editor — recommended) | edit the code | https://code.visualstudio.com | opens |

> ⚠️ Node must be **20 or newer**. If `node -v` shows 16 or 18, install the LTS
> from nodejs.org and reopen your terminal.

### 1.2 Required ONLY for Option B (changing the .NET APIs / database)

Skip this whole section if you're only touching the website.

| Tool | Why | Get it | Check it works |
|---|---|---|---|
| **.NET 8 SDK** | runs the two C# APIs | https://dotnet.microsoft.com/download/dotnet/8.0 | `dotnet --version` → `8.x` |
| **SQL Server** (Express or Developer, free) | the database | https://www.microsoft.com/sql-server/sql-server-downloads | service running |
| **sqlcmd** *(comes with SQL Server tools)* OR **Azure Data Studio** | run the database scripts | https://learn.microsoft.com/sql/azure-data-studio | `sqlcmd -?` |

> macOS/Linux tip: instead of installing SQL Server natively, run it in Docker:
> ```bash
> docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=YourStrong!Passw0rd" \
>   -p 1433:1433 -d mcr.microsoft.com/mssql/server:2022-latest
> ```

---

## Part 2 — Get the code

```powershell
git clone https://github.com/TechRetainerAI/poultrymaster_web.git
cd poultrymaster_web
```

(macOS/Linux: identical.)

---

## Part 3 — Option A: Run the website only  ⭐ recommended

This runs just the website on your machine and talks to our already-running
**development** server in the cloud. **No .NET, no database needed.**

```powershell
# 1. Install the website's dependencies (one time, ~2 min)
npm install

# 2. Create your local settings file from the ready-made template
copy .env.local.example .env.local

# 3. Start the website
npm run dev
```

macOS/Linux: step 2 is `cp .env.local.example .env.local`.

Now open **http://localhost:3000** in your browser.

- Log in with a **dev test account** — ask the project owner for an email +
  password.
- Edit any file under `app/` or `components/` and the page reloads automatically.

> If the dev server crashes or behaves oddly with Turbopack, use the fallback:
> `npm run dev:webpack`

✅ **That's the whole setup for UI work.** Stop here unless the bug is in the C#
backend or the database.

---

## Part 4 — Option B: Run everything locally

Do this only if the bug is in a **.NET API** or the **database**. There are three
services to start: the **database**, the **Farm API**, the **Login API**, and
then the website.

### 4.1 Create the database and load the schema

1. Make sure SQL Server is running and you can connect (e.g. with Azure Data
   Studio or `sqlcmd`).

2. Create an empty database, e.g. `PoultryMasterDev`:

   ```sql
   CREATE DATABASE PoultryMasterDev;
   ```

3. Apply **all 105 migration scripts in number order** (`001_…` → `105_…`).
   They live in `poultrycore/PoultryFarmAPI/Migrations/`. They are safe to
   re-run.

   **Windows (PowerShell)** — run every script in order, stop on first error:
   ```powershell
   Get-ChildItem .\poultrycore\PoultryFarmAPI\Migrations\*.sql |
     Sort-Object Name |
     ForEach-Object {
       Write-Host "Applying $($_.Name)"
       sqlcmd -S localhost -U sa -P "YourStrong!Passw0rd" -d PoultryMasterDev -b -I -i $_.FullName
       if ($LASTEXITCODE -ne 0) { Write-Error "FAILED on $($_.Name)"; break }
     }
   ```

   **macOS/Linux (bash)**:
   ```bash
   for f in $(ls poultrycore/PoultryFarmAPI/Migrations/*.sql | sort); do
     echo "Applying $f"
     sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -d PoultryMasterDev -b -I -i "$f" || { echo "FAILED: $f"; break; }
   done
   ```

   > The `-I` flag (QUOTED_IDENTIFIER ON) is required — a few migrations create
   > filtered indexes that fail without it. Use a login with permission to
   > create tables/procedures (e.g. `sa` locally).

### 4.2 Start the Farm API

`poultrycore/PoultryFarmAPI/` is the main business API. It refuses to start
without a connection string and a JWT secret, so set them with **user-secrets**
(these stay on your machine, never committed):

```powershell
cd poultrycore\PoultryFarmAPI
dotnet user-secrets init
dotnet user-secrets set "ConnectionStrings:PoultryConn" "Server=localhost;Database=PoultryMasterDev;User Id=sa;Password=YourStrong!Passw0rd;TrustServerCertificate=True"
dotnet user-secrets set "JWT:Secret" "change-me-to-a-long-random-string-at-least-32-chars"
dotnet run
```

It starts at **https://localhost:7190** (or **http://localhost:5142**). Leave it
running and open a new terminal for the next API.

### 4.3 Start the Login API

`poultrycore/LoginAPI/User.Management.API/` handles login, accounts, companies
and payments.

```powershell
cd poultrycore\LoginAPI\User.Management.API
dotnet user-secrets init
dotnet user-secrets set "JWT:Secret" "change-me-to-a-long-random-string-at-least-32-chars"
# If its appsettings needs a DB connection too, set it the same way:
dotnet user-secrets set "ConnectionStrings:PoultryConn" "Server=localhost;Database=PoultryMasterDev;User Id=sa;Password=YourStrong!Passw0rd;TrustServerCertificate=True"
dotnet run
```

It starts at **https://localhost:7010** (or **http://localhost:5010**).

> ⚠️ **The `JWT:Secret` MUST be the exact same value on both APIs** (and at least
> 32 characters). If they differ, a token issued by the Login API will be
> rejected by the Farm API and you'll be logged out instantly.

### 4.4 Point the website at your local APIs

Edit `.env.local` (create it from the template first if you haven't):

```
NEXT_PUBLIC_API_BASE_URL=localhost:7190
NEXT_PUBLIC_ADMIN_API_URL=localhost:7010
FARM_API_URL=https://localhost:7190
ADMIN_API_URL=https://localhost:7010
```

Then start the website:

```powershell
npm install   # if you haven't already
npm run dev
```

Open **http://localhost:3000**. You now have the full stack running locally.

---

## Part 5 — Everyday commands

Run these from the repo root:

```powershell
npm run dev          # start the website with hot reload (Turbopack)
npm run dev:webpack  # same, but Webpack (use if Turbopack misbehaves)
npm run build        # production build — also catches most code errors
npm start            # run the built production server
npx tsc --noEmit     # strict TypeScript check (build does NOT fail on type errors)
```

For the APIs (run inside each project folder):

```powershell
dotnet run           # start the API
dotnet build         # compile only
```

> There is **no automated test suite**. `npm run lint` just runs `npm run build`.
> Because `next.config.mjs` sets `ignoreBuildErrors`, the build will NOT fail on
> TypeScript type errors — run `npx tsc --noEmit` if you want real type checks.

---

## Part 6 — Fixing common errors

| What you see | What it means / fix |
|---|---|
| `npm run dev` errors instantly, or `next: command not found` | Run `npm install` first. If it still fails, your Node is too old — install **Node 20+** and reopen the terminal. |
| Website loads but every data page is blank or shows 500 | `.env.local` isn't pointing at a working API. Re-copy `.env.local.example` (Option A) and restart `npm run dev`. |
| You log in then get kicked out immediately | The two APIs have **different `JWT:Secret`** (Option B), or your session expired — log in again. |
| API won't start: *"Connection string 'PoultryConn' not found / is empty"* | Set it with `dotnet user-secrets` (Part 4.2). |
| API won't start: *"JWT:Secret is not configured / too short"* | Set a **32+ character** `JWT:Secret` on **both** APIs (Parts 4.2 & 4.3). |
| API runs but pages error with *"Could not find stored procedure …"* | The database is missing migrations. Re-run the migration loop in Part 4.1. |
| A migration fails mentioning `QUOTED_IDENTIFIER` | You omitted the `-I` flag in the sqlcmd command. Add `-I`. |
| `dotnet run` can't connect to SQL Server | SQL Server isn't running, wrong server/password, or missing `TrustServerCertificate=True` in the connection string. |
| Styles look broken after `git pull` | Dependencies changed — run `npm install` again. |
| HTTPS warning on `https://localhost:7190` | Run `dotnet dev-certs https --trust` once to trust the local dev certificate. |

---

## Part 7 — How the project is organised

```
poultrymaster_web/
├─ app/                         # the website pages (Next.js App Router)
│   ├─ water-*                  #   Water company features
│   ├─ generic-*                #   Generic company features
│   └─ flocks, egg-production…  #   Poultry features
├─ components/
│   └─ ui/                      # shared building blocks (buttons, tables, dialogs)
├─ lib/
│   ├─ api/                     # functions that call the backend (water.ts, generic.ts…)
│   └─ store/auth-store.ts      # who is logged in + which company is active
├─ poultrycore/
│   ├─ PoultryFarmAPI/          # main .NET API (business data)
│   │   └─ Migrations/          #   database scripts 001 → 105 (run in order)
│   └─ LoginAPI/                # .NET API for login / companies / payments
├─ .env.local.example           # copy to .env.local for local dev
├─ README.md                    # short version of this guide
└─ CLAUDE.md                    # deeper architecture notes
```

**Key idea:** the browser only ever talks to the website. The website forwards
API calls server-side to the two .NET APIs. The path decides which API:
`Admin`, `Authentication`, `Payments`, `UserProfile`, `Companies` → **Login API**;
everything else → **Farm API**.

There are **three company types** — Water, Poultry, Generic — sharing one
codebase. The active company's type decides which menus show.

---

## Part 8 — (Optional) Deploying

Deployment is on **Google Cloud Run** via Cloud Build. You normally won't need
this — the project owner handles releases. For reference:

```bash
# Website
gcloud builds submit . --config=cloudbuild.web.yaml --substitutions=_SERVICE_NAME=poultrymaster-web-dev

# Farm API
gcloud builds submit . --config=poultrycore/cloudbuild.farm.yaml --ignore-file=poultrycore/.gcloudignore.farm

# Login API
gcloud builds submit . --config=poultrycore/cloudbuild.login.yaml
```

`docker-compose.yml` in the root only builds/runs the **website** container
(pointed at the cloud APIs) — it does **not** start a local database.

---

## Part 9 — Getting unblocked

If a step here doesn't work, send the project owner:
1. The **exact command** you ran, and
2. The **full error message** (copy all of it).

That's the fastest way to get help.
