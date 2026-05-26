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
