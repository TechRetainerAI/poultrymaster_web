# Dev Setup & Known Issues

This document records issues hit while getting the frontend build and the email/auth
flow working locally, **why** each happened, the **fix**, and what's already in place
so that **anyone who pulls this branch does not hit the same wall**.

Repo layout reminder (see `poultrycore-main/CLAUDE.md` for the full version):

- `poultrycore-main/` — Next.js 16 / React 19 frontend. **All `npm` commands run from here**, not the repo root.
- `poultrycore_Backend/PoultryFarmAPI/` — .NET 8 Farm API (business modules, email sending).
- `poultrycore_Backend/LoginAPI/User.Management.API/` — .NET 8 Login API (auth, JWT issuing, OTP emails).

---

## TL;DR — first-time setup checklist

After cloning/pulling this branch, before running anything:

1. **Frontend:** `cd poultrycore-main && npm install` (run npm from this folder only).
2. **Do not** create or leave a `package-lock.json` / `pnpm-lock.yaml` in the repo root (`poultrymaster_web/`). Only `poultrycore-main/` owns a lockfile. (Already guarded — see Issue 1.)
3. **Backend secrets (per machine, not committed):** set `JWT:Secret`, the DB connection string, and `EmailConfiguration:*` via `dotnet user-secrets` for **both** the Farm API and the Login API. Use the script in [Appendix A](#appendix-a--one-shot-user-secrets-setup).
4. The **`JWT:Secret` must be byte-for-byte identical** in both APIs, or the Farm API rejects Login tokens with 401. (See Issue 3.)
5. Restart both APIs after changing secrets (`dotnet user-secrets` changes are read at startup).

---

## Issue 1 — Frontend build fails: `Can't resolve 'tailwindcss'` + fatal OOM

### Symptom
`npm run build` (or `dev`) crashed with:

```
Error: Can't resolve 'tailwindcss' in 'C:\Users\...\poultrymaster_web'
...
# Fatal process out of memory: Re-embedded builtins
```

Note the path in the error: `poultrymaster_web` (the **parent** of `poultrycore-main`), which has no `node_modules`.

### Why
Next.js detects the "workspace root" by walking **up** the directory tree looking for a
lockfile. An empty, accidental `package-lock.json` was sitting in the repo root
(`poultrymaster_web/package-lock.json`, contents `{ "packages": {} }`). Next picked the
parent as the root, so:

- Module resolution looked for `tailwindcss` in `poultrymaster_web/node_modules` (doesn't exist) instead of `poultrycore-main/node_modules` (where it is installed).
- The file-tracing pass against the wrong root looped and exhausted memory → OOM.

### Fix applied
- Deleted the stray `poultrymaster_web/package-lock.json`.
- **Pinned the root** in `poultrycore-main/next.config.mjs` so this can't recur even if a
  parent lockfile reappears:

  ```js
  const projectRoot = dirname(fileURLToPath(import.meta.url))
  const nextConfig = {
    outputFileTracingRoot: projectRoot,
    turbopack: { root: projectRoot },
    // ...
  }
  ```

### Prevention for people who pull
Already handled — the `next.config.mjs` pin is committed. The build resolves modules and
traces files against `poultrycore-main/` regardless of stray parent lockfiles. Just
remember to run `npm` commands **from `poultrycore-main/`**.

---

## Issue 2 — Swagger returns 401 on every `/api/Email/*` call, no way to send a token

### Symptom
Calling e.g. `POST https://localhost:7190/api/Email/send-credentials` from Swagger returned:

```
401  Undocumented
www-authenticate: Bearer        (bare — no error="invalid_token")
content-length: 0
```

### Why
`EmailController` is decorated `[Authorize]` at the class level, so every endpoint needs a
valid JWT. Swagger was set up with a bare `AddSwaggerGen()` — **no security definition** —
so there was **no "Authorize" button** and no way to attach a bearer token. The request
went out with no `Authorization` header, and the API correctly challenged with `401`. (The
bare `Bearer` with no `error=` is the tell-tale sign of *no token sent*, as opposed to an
expired/invalid one.)

### Fix applied
Added a JWT bearer security scheme to `AddSwaggerGen(...)` in
`poultrycore_Backend/PoultryFarmAPI/Program.cs`, which adds the **Authorize** button to
Swagger UI.

### How to use it (and prevention for pullers)
The Swagger change is committed, so the Authorize button is there after you build/run.
To test a protected endpoint:

1. Get a JWT — either copy `auth_token` from the running web app's `localStorage`
   (DevTools → Application → Local Storage), or log in via the Login API
   (`POST https://localhost:7010/api/Authentication/login`; if 2FA is on, follow with
   `/api/Authentication/login-2FA`).
2. In Swagger click **Authorize**, paste the **raw** token (no `Bearer ` prefix — the
   scheme adds it), Authorize, close.
3. Run the endpoint.

> If an endpoint is genuinely meant to be called **before** a user has a token (e.g. part
> of self-registration), the correct fix is `[AllowAnonymous]` on that specific action —
> not loosening the whole controller.

---

## Issue 3 — "Failed to send email (status 401)" from the web app (JWT issuer mismatch)

### Symptom
The web app's report-email feature failed with `Failed to send email (status 401)`. The
email was never actually attempted — the 401 came from the `[Authorize]` gate. (Email-send
failures return **503/500** with a message, never 401, so a 401 here is always auth.)

### Why
The Login API and Farm API disagreed on the JWT **issuer**:

| | Effective `JWT:ValidIssuer` |
|---|---|
| **Login API** stamps into every token | `https://UserManagementAPI.techretainer.com` |
| **Farm API** required (`ValidateIssuer = true`) | `https://usermanagementapi.poultrycore.com` |

Different domains → the Farm API rejected **every** Login-minted token → 401 on all
`[Authorize]` endpoints (Email, Water, Generic, everything). The signing secret matched;
only the issuer was wrong. (The Farm API has `ValidateAudience = false`, so audience was
never the problem.)

### Fix applied
Aligned the Farm API's expected issuer to what the Login API actually issues, in the
**committed** config (so pullers get it):

- `poultrycore_Backend/PoultryFarmAPI/appsettings.json`
- `poultrycore_Backend/PoultryFarmAPI/appsettings.Production.json`

Both now have `"JWT:ValidIssuer": "https://UserManagementAPI.techretainer.com"`.

> The Login API was intentionally **not** changed — it is the issuer, so its value is
> authoritative; changing it would invalidate every existing token. We changed the
> *validator* (Farm API) to expect the real issuer.

### Prevention for people who pull
Committed in appsettings — no action needed for local dev.

**Production caveat:** if a deploy sets `JWT__ValidIssuer` as an environment variable, it
**overrides** the appsettings file. Make sure the Farm API Cloud Run service's
`JWT__ValidIssuer` env (if set) equals the Login API's issuer, or prod will 401 the same
way. Likewise `JWT__Secret` must match across both services in every environment.

---

## Issue 4 — Email doesn't send locally (SMTP config not committed)

### Symptom
After auth was fixed, email could still fail because SMTP settings live in **user secrets**
(per machine) and are blank in the committed `appsettings.json` — so a fresh clone has no
mail config.

### Why (by design)
`EmailConfiguration:Password` is a live secret (Resend API key). It must **never** be
committed. Both APIs read `EmailConfiguration:*`; the values are supplied via
`dotnet user-secrets` (dev) or environment variables (prod).

### Fix / setup
Set the `EmailConfiguration:*` keys in **both** the Farm API and Login API user-secret
stores. See [Appendix A](#appendix-a--one-shot-user-secrets-setup).

### Prevention for people who pull
Secrets can't be shared via git. A teammate must run the setup script with values obtained
from the team's secret manager / password vault — **not** from this file or chat history.

> **Security note:** the Resend key used during this session was pasted into a chat and
> should be rotated in the Resend dashboard. Also, Resend only sends from a **verified
> domain** — the `From` address (`Techretainer@payrollhaven.com`) must belong to a domain
> verified in the Resend account, or sends are rejected (with a 5xx, not a 401).

---

## Appendix A — one-shot user-secrets setup

Run from the repo root. Replace the placeholder values with the real ones from your team's
secret store. `JWT:Secret` **must be identical** in both blocks.

```powershell
# ---- Farm API ----
cd poultrycore_Backend/PoultryFarmAPI
dotnet user-secrets set "ConnectionStrings:PoultryConn" "<DB connection string>"
dotnet user-secrets set "JWT:Secret"                    "<shared JWT secret, >=32 chars>"
dotnet user-secrets set "EmailConfiguration:SmtpServer" "smtp.resend.com"
dotnet user-secrets set "EmailConfiguration:Port"       "465"
dotnet user-secrets set "EmailConfiguration:UseSsl"     "true"
dotnet user-secrets set "EmailConfiguration:UserName"   "resend"
dotnet user-secrets set "EmailConfiguration:Password"   "<RESEND_API_KEY>"
dotnet user-secrets set "EmailConfiguration:From"       "<verified-sender@yourdomain>"

# ---- Login API (same email + same JWT secret) ----
cd ../LoginAPI/User.Management.API
dotnet user-secrets set "ConnectionStrings:ConnStr"     "<DB connection string>"
dotnet user-secrets set "JWT:Secret"                    "<shared JWT secret, >=32 chars>"
dotnet user-secrets set "EmailConfiguration:SmtpServer" "smtp.resend.com"
dotnet user-secrets set "EmailConfiguration:Port"       "465"
dotnet user-secrets set "EmailConfiguration:UseSsl"     "true"
dotnet user-secrets set "EmailConfiguration:UserName"   "resend"
dotnet user-secrets set "EmailConfiguration:Password"   "<RESEND_API_KEY>"
dotnet user-secrets set "EmailConfiguration:From"       "<verified-sender@yourdomain>"
```

Verify with `dotnet user-secrets list` in each project. Restart both APIs afterward.

> Note: the Farm API connection-string key is `ConnectionStrings:PoultryConn`; the Login
> API's is `ConnectionStrings:ConnStr` — they differ, so don't copy-paste the key name.

---

## Quick triage: what a 401 means here

- **Bare `www-authenticate: Bearer`, empty body** → no token was sent (Swagger not
  authorized, or a fetch missing the header).
- **`www-authenticate: Bearer error="invalid_token"`** → a token was sent but rejected:
  check `JWT:Secret` match (Issue 3) and `JWT:ValidIssuer` match between the two APIs.
- **CORS headers present on the 401 with `Origin: https://localhost:7190`** → the call hit
  the Farm API **directly** (e.g. Swagger), not through the Next.js `/api/proxy/*`.
- A 401 labelled "failed to send email" is **still auth**, not SMTP — email failures are
  503/500.
