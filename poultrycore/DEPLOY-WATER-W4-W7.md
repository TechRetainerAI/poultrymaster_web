# Redeploy: Water Company W4–W7 + frontend pages

The Farm API endpoints added in migrations 047–052 (and the matching frontend
pages) won't show up in production until both halves of the stack are
redeployed. This is a checklist; the actual commands live below.

## 1. Verify migrations are applied

You already applied 047–052 to `PoultryMasterDev` during the build session.
Re-confirm before deploying — the API will return SqlException → 500 if any
SP is missing (the new `GlobalExceptionMiddleware` will at least make the
error legible in the response body).

```powershell
sqlcmd -S "34.39.109.13" -U "sqlserver" -d "PoultryMasterDev" -C -h-1 -Q "SELECT 'SP missing: ' + needed.name
  FROM (VALUES
    ('spWaterCompany_Setup'),('spWaterCompany_GetProfile'),
    ('spWaterExpense_GetAll'),('spWaterExpense_Approve'),('spWaterCashAccount_GetAll'),
    ('spWaterCashTransfer_Approve'),('spWaterCustomerLedger_AddEntry'),
    ('spWaterStaff_GetAll'),('spWaterPayrollRun_MarkPaid'),
    ('spWaterMaintenanceLog_DueAlerts')
  ) AS needed(name)
  WHERE NOT EXISTS (SELECT 1 FROM sys.procedures p WHERE p.name = needed.name);"
```

Zero rows back = clean. Anything listed = re-run the matching migration file
in `poultrycore/PoultryFarmAPI/Migrations/`.

## 2. Redeploy the Farm API (Cloud Run dev)

The dev service is `poultrymaster-farm-api-dev` in `europe-west1`. Override
`_SERVICE_NAME` so the existing `cloudbuild.farm.yaml` retargets the dev
Cloud Run service instead of the production one:

```powershell
# From this folder: C:\Users\CODEWITHFIIFI\Downloads\poultrycore-main\poultrycore-main\poultrycore
gcloud builds submit . `
  --config=cloudbuild.farm.yaml `
  --substitutions=_SERVICE_NAME=poultrymaster-farm-api-dev `
  --ignore-file=.gcloudignore.farm
```

What this does:
1. Builds the Docker image from `PoultryFarmAPI/Dockerfile` (includes the
   new `GlobalExceptionMiddleware`, W4–W7 controllers, services, models).
2. Pushes to Artifact Registry with two tags (`$BUILD_ID`, `latest`).
3. Deploys to Cloud Run service `poultrymaster-farm-api-dev` on port 8080.

Smoke check after deploy:

```powershell
# Should return 200 OK with [] (no logs yet for this farm), not 404
curl "https://poultrymaster-farm-api-dev-t6tn7geswq-ew.a.run.app/api/Water/expenses?farmId=8b568825-56e5-438f-8219-e0284ce7bc7d"

# Should return 200 OK with the seeded profile
curl "https://poultrymaster-farm-api-dev-t6tn7geswq-ew.a.run.app/api/Water/company?farmId=8b568825-56e5-438f-8219-e0284ce7bc7d"
```

## 3. Redeploy the Next.js frontend

The new water pages (`/water-company-setup`, `/water-expenses`,
`/water-cash-accounts`, `/water-staff`, `/water-payroll`,
`/water-maintenance`) and the extended `lib/api/water.ts` only ship when the
Next.js side is rebuilt and deployed. How you deploy the frontend depends on
where it's hosted — common options:

```powershell
# If frontend is on Cloud Run too (mirrors the Farm API setup):
gcloud builds submit ..\ --config=..\cloudbuild.yaml

# Or via Vercel (if that's where the *.run.app frontend mirror is):
cd ..
vercel --prod
```

Open `.env.production` to confirm `NEXT_PUBLIC_API_BASE_URL` points at the
dev Farm API URL above.

## 4. End-to-end check in the browser

1. Log in as the user whose farm has `Type='Water'` (the test farm
   `8b568825-…` was flipped to Water during the build session — flip it back
   to Generic if you need the Generic Company pages to work for that account).
2. Sidebar should now show new groups under Water: **Money** (Expenses, Cash
   & Accounts), **People** (Staff, Payroll), **Admin** (Maintenance, Setup).
3. Visit `/water-company-setup` first — if the profile already exists from
   the SQL-side smoke test, the form loads filled. Save once to verify the
   PUT endpoint works.
4. Try recording an expense → submit → approve → confirm the linked cash
   account's `currentBalance` drops by the expense amount on
   `/water-cash-accounts`.

## What I did NOT touch

- The Water dashboard (`/water-dashboard`) doesn't yet surface the new
  W4–W7 totals (today's expenses, cash at hand, payroll due, maintenance
  alerts). Wiring those tiles is a follow-up — the data is all there via
  `getWaterDashboardSummary` + the new `listWater*` calls.
- No automated tests for the new pages; the existing project doesn't have
  Playwright/Jest configured for the Next.js app.
- The `Farms.Type='Water'` requirement is enforced by `spWaterCompany_Setup`.
  Any farm without that Type will get a clean error message from the new
  global exception middleware rather than a 500 stack trace.

---

## Rotating SQL passwords on Cloud Run (lessons learned, 2026-05-24)

Three gcloud footguns hit during a dev password rotation. Avoid them next time.

### 1. Don't use `^DELIM^` with a delimiter that might appear in values

`--update-env-vars "^@^KEY=VALUE"` tells gcloud `@` is the inter-var separator. SQL passwords that contain `@` (very common — `Techretainer@77`) will be truncated at the first `@` and the rest of the connection string will become **bogus extra env vars** with names like `77;Pooling` and values like `False;TrustServerCertificate=True`. The container will still start because the truncated `Password=...` value is what authenticates, but **SQL Server then rejects the login** (error 18456). The bogus env vars also persist across subsequent updates.

**Rule:** for a single env var with no `,` in its value, just omit the `^DELIM^` prefix entirely. Default delimiter is `,`. Connection strings use `;` and `=` which are safe.

```powershell
# Wrong
gcloud run services update <svc> --update-env-vars="^@^ConnectionStrings__PoultryConn=Data Source=...;Password=Techretainer@77;..."
# Right
gcloud run services update <svc> --update-env-vars="ConnectionStrings__PoultryConn=Data Source=...;Password=Techretainer@77;..."
```

### 2. `--env-vars-file` is full REPLACE, not merge

A YAML with one key removes every other env var on the service. If the YAML doesn't include `JWT__Secret`, the new revision will throw on startup. Only use `--env-vars-file` when the YAML is **complete** (i.e. lists every env var the service needs).

To update only one var, use `--update-env-vars KEY=VALUE` (merge) instead.

### 3. Failed revisions still become the "latest configured"

When a new revision fails health check, Cloud Run keeps the working revision serving — but the failed revision is now the **base** for the next `--update-env-vars` call. So a failed `--env-vars-file` deploy that wiped everything to one var means every subsequent `--update-env-vars` builds on top of that empty-vars revision, even if it's not serving.

**To recover:** dump the full env-var map from the last working revision and apply it via `--env-vars-file` (this time using a complete YAML), which forces the new revision back to the correct state.

```powershell
# Extract working revision's env vars to a clean YAML
gcloud run revisions describe <svc>-<rev> --region=europe-west1 --format=json `
  | python -c "import sys,json;r=json.load(sys.stdin);env=r['spec']['containers'][0].get('env',[]);[print(f\"{e['name']}: '{e.get('value','')}'\") for e in env]" `
  > restore.yaml
# Apply (after manual review to ensure all values are correct and quoted safely)
gcloud run services update <svc> --region=europe-west1 --env-vars-file=restore.yaml
```

### Recommended rotation procedure (zero-touch on prod)

1. **Create a new SQL login** for dev only, separate from any prod-shared login:
   ```sql
   USE master;
   CREATE LOGIN [sqlserver_dev_<yyyymmdd>] WITH PASSWORD = N'<strict-alnum-32-chars>', CHECK_POLICY = OFF;
   USE PoultryMasterDev;
   CREATE USER [sqlserver_dev_<yyyymmdd>] FOR LOGIN [sqlserver_dev_<yyyymmdd>];
   ALTER ROLE db_owner ADD MEMBER [sqlserver_dev_<yyyymmdd>];
   ```
2. **Generate password with strict alphanumeric only** — no `@`, no `+`, no `=`. SQL accepts any character; the limits are CLI/YAML escaping not the DB.
3. **Test the new login from sqlcmd** before touching Cloud Run:
   ```powershell
   $env:SQLCMDPASSWORD = "<new-password>"; sqlcmd -S 34.39.109.13 -U sqlserver_dev_<yyyymmdd> -d PoultryMasterDev -C -Q "SELECT 1"
   ```
4. **Pre-build the complete env-vars YAML** for each affected service (every var, not just the changed one). Review it carefully.
5. **Apply via `--env-vars-file`** to each dev service. Verify each new revision is `Ready=True` and serving 100% traffic before moving to the next.
6. **Smoke-test the running services** with a real DB call (e.g. `/api/Water/dashboard/summary?farmId=...`).
7. **For prod**: same procedure but in a maintenance window; both prod Login API + Farm API use `sqlserver` and `Techretainer` logins respectively — rotate them as needed.
8. **Don't paste passwords into chat or commit them anywhere.** If a password ends up in a transcript, rotate it.

### Env vars exposed by chat 2026-05-24 (rotate when convenient)

- `Techretainer@77` — SQL Server password for both `sqlserver` and `Techretainer` logins. Still live on prod Login API (`poultrymaster-api-git`), prod Farm API (`poultrymaster-farm-api-git` via Techretainer login), and both dev APIs.
- Dev Farm API `JWT__Secret` (`3DB8kQxRYazKdR1kpFBf1MbQksZLUMOtSsg1kteaJKY1QwTwBRU3iRTUjJia5ff+`). Must rotate in pair with the dev Login API's `JWT__Secret` since they sign each other's tokens.

