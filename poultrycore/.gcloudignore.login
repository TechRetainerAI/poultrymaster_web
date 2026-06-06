# Use only for Login API Cloud Build from inside poultrycore/:
#   gcloud builds submit . --config=cloudbuild.login.yaml --ignore-file=.gcloudignore.login
#
# Whitelist exactly what poultrycore/Dockerfile needs to build the Login API image.

*
!cloudbuild.login.yaml
!Dockerfile
!LoginAPI/
!LoginAPI/**

# Re-exclude local build artifacts inside the kept tree.
LoginAPI/**/bin/
LoginAPI/**/obj/
LoginAPI/**/publish/
LoginAPI/Tools/

# Local-dev-only secrets overlay. Loaded by Program.cs via AddJsonFile(optional:true).
# Cloud Run uses env vars (EmailConfiguration__*) — never ship local creds in the image.
LoginAPI/**/appsettings.Local.json
