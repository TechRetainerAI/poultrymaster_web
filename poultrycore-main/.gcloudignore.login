# Used only for Login API builds from monorepo root, e.g.:
#   gcloud builds submit --config cloudbuild.login.yaml --ignore-file=.gcloudignore.login .
#
# Root .gcloudignore excludes poultrycore/ (Next.js source deploy). This file must NOT,
# so Cloud Build receives LoginAPI + Dockerfile.

.git/
.next/
node_modules/
out/
.vercel/
*.tsbuildinfo
.env.local
.env
.env.production

# Large / irrelevant for Login API image (speeds root `gcloud builds submit`)
deploy/
farm-registry-portal/node_modules/
**/bin/
**/obj/
**/.vs/
PoultryFarmAPI/publish/
