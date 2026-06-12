# After GitHub blocked your push (secrets / push protection)

## Repo policy

Tracked `appsettings*.json` files use **empty** secrets and connection strings. Configure real values with **User Secrets** (local) or **environment variables** (Cloud Run / Plesk).

## Stripe (LoginAPI)

1. In [Stripe Dashboard](https://dashboard.stripe.com) → **Developers → API keys** — copy keys there (do not paste them into committed files).
2. Local (.NET User Secrets), from `LoginAPI\User.Management.API`:

```powershell
cd LoginAPI\User.Management.API
dotnet user-secrets set "StripeSettings:PrivateKey" "<paste secret key from Stripe>"
dotnet user-secrets set "StripeSettings:PublicKey" "<paste publishable key from Stripe>"
dotnet user-secrets set "StripeSettings:WHSecret" "<paste webhook signing secret from Stripe>"
```

**Cloud Run / production:** set:

- `StripeSettings__PrivateKey`
- `StripeSettings__PublicKey`
- `StripeSettings__WHSecret`

## Flatten git history (required if secrets were ever committed)

GitHub scans **every commit** you push. Old commits with secrets will still fail until history is rewritten.

```powershell
cd C:\Users\CODEWITHFIIFI\Desktop\gg\poultrycore\PoultryPro
git checkout initial-upload
git add -A
git rm --cached PoultryFarmAPI/publish.zip 2>$null
git add -A
git branch backup-before-rewrite
git reset --soft main
# If local main is stale:  git fetch origin && git reset --soft origin/main

git commit -m "Add PoultryPro backend (no secrets in repo)"
git push -u origin initial-upload --force
```

## If push is still blocked

1. Read the **full** `remote:` message — it lists file paths.  
2. Search the repo for remaining patterns:

```powershell
cd PoultryPro
Get-ChildItem -Recurse -Include *.json,*.md,*.cs,*.config -File |
  Select-String -Pattern 'Password=|PrivateKey|api_key|ghp_|github_pat_'
```

3. Remove or redact matches, then repeat **reset --soft** + **commit** + **force push**.
