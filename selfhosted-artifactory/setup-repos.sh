#!/usr/bin/env bash
# Set the admin password, create or update the Maven repositories the Jenkinsfile
# expects, and print a non-expiring access token for Jenkins (local use only).
# Safe to rerun. Reads ./.env; ARTIFACTORY_URL defaults to http://localhost:8082.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
if [[ -f $here/.env ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$here/.env"
  set +a
fi
: "${ARTIFACTORY_ADMIN_PASSWORD:?set ARTIFACTORY_ADMIN_PASSWORD in .env}"
url=${ARTIFACTORY_URL:-http://localhost:8082}
url=${url%/}/artifactory

api() {
  local creds=$1
  shift
  curl -sS --config <(printf 'user = "%s"\n' "$creds") "$@"
}

echo "==> Waiting for $url"
for _ in $(seq 1 60); do
  curl -fsS "$url/api/system/ping" 2>/dev/null | grep -q OK && break
  sleep 5
done
curl -fsS "$url/api/system/ping" | grep -q OK || { echo "No answer from $url" >&2; exit 1; }

echo "==> Admin password"
admin="admin:$ARTIFACTORY_ADMIN_PASSWORD"
default=password
if [[ $(api "$admin" -o /dev/null -w '%{http_code}' "$url/api/repositories") == 200 ]]; then
  echo "    already set"
else
  printf '{"userName":"admin","oldPassword":"%s","newPassword1":"%s","newPassword2":"%s"}' \
      "$default" "$ARTIFACTORY_ADMIN_PASSWORD" "$ARTIFACTORY_ADMIN_PASSWORD" |
    api "admin:$default" -f -X POST -H 'Content-Type: application/json' --data-binary @- \
      "$url/api/security/users/authorization/changePassword" >/dev/null ||
    { echo "Could not set the admin password. ARTIFACTORY_ADMIN_PASSWORD needs 8+ characters" \
        "with upper case, lower case and a digit." >&2; exit 1; }
  echo "    changed from the default"
fi

echo "==> Repositories"
api "$admin" -f -X PATCH -H 'Content-Type: application/yaml' --data-binary @- \
  "$url/api/system/configuration" <<'EOF'
localRepositories:
  petclinic-maven-release-local:
    type: maven
    repoLayout: maven-2-default
    handleReleases: true
    handleSnapshots: false
  petclinic-maven-snapshot-local:
    type: maven
    repoLayout: maven-2-default
    handleReleases: false
    handleSnapshots: true
remoteRepositories:
  petclinic-maven-central-remote:
    type: maven
    repoLayout: maven-2-default
    url: "https://repo.maven.apache.org/maven2/"
  petclinic-jfrog-releases-remote:
    type: maven
    repoLayout: maven-2-default
    url: "https://releases.jfrog.io"
virtualRepositories:
  petclinic-maven:
    type: maven
    repoLayout: maven-2-default
    repositories:
      - petclinic-maven-release-local
      - petclinic-maven-snapshot-local
      - petclinic-maven-central-remote
    defaultDeploymentRepo: petclinic-maven-snapshot-local
EOF
echo
echo "==> Token for Jenkins"
token=$(api "$admin" -f -X POST "$url/api/security/token" -d username=admin \
  --data-urlencode scope=applied-permissions/user -d expires_in=0 |
  tr -d '\n' | sed -E 's/.*"access_token" *: *"([^"]+)".*/\1/')
[[ $token == ey* ]] || { echo "No access token in the response" >&2; exit 1; }

echo
echo "Done: $url/petclinic-maven"
echo "Set this in jenkins/.env, then run docker compose up -d --force-recreate in jenkins/:"
echo "JFROG_SELFHOSTED_TOKEN=$token"
