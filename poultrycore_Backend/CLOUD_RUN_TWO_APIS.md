# Deploy **two** APIs on Google Cloud Run

## GitHub → Cloud Run “Deploy from repository”

Cloud Build uses the **repository root** and expects **`Dockerfile`** there.

This repo includes a **root `Dockerfile`** that builds **LoginAPI** only.  
If you only wired one Cloud Run service from GitHub, it should be the **Login / User Management** API.

For **PoultryFarmAPI**, add a **second Cloud Run service**. This repo includes **`cloudbuild.yaml`** (default GCP filename) and **`cloudbuild.farm.yaml`** (same pipeline) at the root (build → push → deploy).

### A) GitHub trigger for Farm API (recommended)

1. **Push** `cloudbuild.yaml` (and/or `cloudbuild.farm.yaml`) to your GitHub branch (same repo as Login API).

2. In **Google Cloud Console** → **Cloud Build** → **Triggers** → **Create trigger**.

3. Connect **GitHub** → repo `TechRetainerAI/Poultrymaster_api` → branch (e.g. `^initial-upload$` or `^main$`).

4. **Configuration**: *Cloud Build configuration file (yaml or json)*  
   - **Location**: *Repository*  
   - **Path**: `cloudbuild.yaml` (**recommended** — matches GCP default) or `cloudbuild.farm.yaml`  
   - If you leave the default path, GCP looks for **`cloudbuild.yaml`** only; using another name without changing the field causes *File cloudbuild.yaml not found*.

5. Open **Substitution variables** (or edit the yaml) and confirm:
   - `_REGION` — same as Login (e.g. `europe-west1`).
   - `_SERVICE_NAME` — new service name (default `poultrymaster-farm-api-git`). Must **not** be the same as the Login service.
   - `_AR_REPO_PATH` — must match your Artifact Registry path for this GitHub repo.  
     Copy from the Login build log: the segment after `PROJECT_ID/` and before the final image name, e.g.  
     `cloud-run-source-deploy/techretainerai-poultrymaster_api`  
     (If your Login image path differs, paste that middle part here.)

6. **Service account**: use the same / similar as the working Login trigger (needs **Artifact Registry Writer** + **Cloud Run Admin**).

7. Run the trigger (push a commit or “Run trigger”).  
   You should get a second URL, e.g. `https://poultrymaster-farm-api-git-....run.app`.

8. **Cloud Run** → open the **new** service → **Edit & deploy new revision** → set env vars:
   - `ConnectionStrings__PoultryConn`
   - `JWT__Secret`, `JWT__ValidAudience`, `JWT__ValidIssuer` (**same signing secret / rules as Login API** if Farm validates those tokens)
   - `ASPNETCORE_ENVIRONMENT=Production` if needed  
   - `AllowedOrigins__0` (and more indexes) if your app uses that config

9. If the API should be callable without Google IAM: **Security** → **Allow unauthenticated invocations** (same idea as Login), or attach **Cloud Run Invoker** to your users.

### B) Manual `docker` + `gcloud` (no second trigger)

See **sections 3 and 5** below (build from `PoultryFarmAPI/`, push, `gcloud run deploy`).

---

Cloud Run runs **one container per service**. You deploy:

| API | Folder | Cloud Run service name (example) |
|-----|--------|-----------------------------------|
| **Login / User Management** | `LoginAPI/` | `poultrymaster-login-api` |
| **Farm / production / flocks** | `PoultryFarmAPI/` | `poultrymaster-farm-api` |

Each service gets its **own HTTPS URL**. Your Next.js app (or mobile) calls **both** base URLs.

---

## 1. One-time GCP setup

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud services enable run.googleapis.com artifactregistry.googleapis.com
gcloud artifacts repositories create poultrycore-apis \
  --repository-format=docker \
  --location=us-central1
gcloud auth configure-docker us-central1-docker.pkg.dev
```

Replace `us-central1` if you use another region.

---

## 2. Build & push **LoginAPI**

```bash
cd LoginAPI
docker build -t us-central1-docker.pkg.dev/YOUR_PROJECT_ID/poultrycore-apis/login-api:latest .
docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/poultrycore-apis/login-api:latest
```

---

## 3. Build & push **PoultryFarmAPI**

```bash
cd ../PoultryFarmAPI
docker build -t us-central1-docker.pkg.dev/YOUR_PROJECT_ID/poultrycore-apis/farm-api:latest .
docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/poultrycore-apis/farm-api:latest
```

---

## 4. Deploy **Login** service

```bash
gcloud run deploy poultrymaster-login-api \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT_ID/poultrycore-apis/login-api:latest \
  --region us-central1 \
  --platform managed \
  --port 8080 \
  --allow-unauthenticated
```

Add secrets via **environment variables** (Console or CLI), e.g.:

- `ConnectionStrings__ConnStr` — SQL connection string  
- `JWT__Secret`, `JWT__ValidAudience`, `JWT__ValidIssuer`  
- `StripeSettings__PrivateKey`, `StripeSettings__PublicKey`, `StripeSettings__WHSecret`  
- Email settings if used  

Use **Secret Manager** for production instead of plain `--set-env-vars` when possible.

---

## 5. Deploy **Farm** service

```bash
gcloud run deploy poultrymaster-farm-api \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT_ID/poultrycore-apis/farm-api:latest \
  --region us-central1 \
  --platform managed \
  --port 8080 \
  --allow-unauthenticated
```

Set at least:

- `ConnectionStrings__PoultryConn` — SQL connection string  
- `JWT__Secret` — **must match** what LoginAPI uses to sign tokens (same secret both APIs trust)  
- `JWT__ValidAudience`, `JWT__ValidIssuer` — must match your token validation config  

`ASPNETCORE_ENVIRONMENT=Production` is usually set automatically or add `--set-env-vars ASPNETCORE_ENVIRONMENT=Production`.

---

## 6. Wire the **frontend**

After deploy, Cloud Run shows URLs like:

- `https://poultrymaster-login-api-xxxxx-uc.a.run.app`
- `https://poultrymaster-farm-api-xxxxx-uc.a.run.app`

Point your Next.js env (e.g. `NEXT_PUBLIC_*` or server-side API base URLs) to:

- **Auth / employees / admin** → Login API URL  
- **Flocks, production, sales, health, etc.** → Farm API URL  

CORS: allow your web app origin on **both** APIs if the browser calls them directly.

---

## 7. SQL Server on the internet

Cloud Run has **no fixed outbound IP** on the default tier. Your SQL server must:

- Allow Cloud Run’s connections (often via **Cloud SQL** with connector, or **VPC connector** + static IP, or a host that allows broad SSL access — your security team should decide).

---

## Summary

- **Two images** → **two `docker build` / `push`** → **two `gcloud run deploy`** commands.  
- **Two URLs** in the client config.  
- **Same JWT signing secret** (and matching issuer/audience rules) on both APIs if Farm validates Login tokens.

More detail for LoginAPI only: `LoginAPI/CLOUD_RUN.md`.
