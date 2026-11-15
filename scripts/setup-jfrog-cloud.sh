#!/usr/bin/env bash
# Create or update the repositories the pipeline uses on a JFrog Cloud instance.
# Safe to rerun. Asks for an admin-scoped access token unless JFROG_ACCESS_TOKEN is set.
#
#   JFROG_URL=https://<name>.jfrog.io scripts/setup-jfrog-cloud.sh
set -euo pipefail

: "${JFROG_URL:?set JFROG_URL, for example https://<name>.jfrog.io}"
if [[ -z ${JFROG_ACCESS_TOKEN:-} ]]; then
  read -rsp 'Admin-scoped access token: ' JFROG_ACCESS_TOKEN && echo
fi
: "${JFROG_ACCESS_TOKEN:?no access token given}"
JFROG_URL=${JFROG_URL%/}
api=$JFROG_URL/artifactory/api

jcurl() {
  curl -sS --retry 3 --retry-all-errors --connect-timeout 10 \
    --config <(printf 'header = "Authorization: Bearer %s"\n' "$JFROG_ACCESS_TOKEN") "$@"
}

# repo <key> <JSON fields>: create the repository, or update it if it exists.
repo() {
  local url=$api/repositories/$1 method=PUT out
  if [[ $(jcurl -o /dev/null -w '%{http_code}' "$url") == 200 ]]; then
    method=POST
  fi
  out=$(jcurl --fail-with-body -X "$method" -H 'Content-Type: application/json' \
    -d "{\"key\":\"$1\",$2}" "$url") || { echo "$method $1 failed: $out" >&2; exit 1; }
  echo "    $method $1"
}

echo "==> $JFROG_URL"
[[ $(jcurl "$api/system/ping") == OK ]] || { echo "Ping failed; check JFROG_URL and the token" >&2; exit 1; }

repo petclinic-maven-release-local '"rclass":"local","packageType":"maven","handleSnapshots":false'
repo petclinic-maven-snapshot-local '"rclass":"local","packageType":"maven","handleReleases":false'
repo petclinic-maven-central-remote '"rclass":"remote","packageType":"maven","url":"https://repo.maven.apache.org/maven2/"'
repo petclinic-jfrog-releases-remote '"rclass":"remote","packageType":"maven","url":"https://releases.jfrog.io"'
repo petclinic-maven '"rclass":"virtual","packageType":"maven",
  "repositories":["petclinic-maven-release-local","petclinic-maven-snapshot-local","petclinic-maven-central-remote"],
  "defaultDeploymentRepo":"petclinic-maven-snapshot-local"'
repo petclinic-docker-local '"rclass":"local","packageType":"docker"'
repo petclinic-dockerhub-remote '"rclass":"remote","packageType":"docker","url":"https://registry-1.docker.io/","enableTokenAuthentication":true'
repo petclinic-docker '"rclass":"virtual","packageType":"docker",
  "repositories":["petclinic-docker-local","petclinic-dockerhub-remote"],
  "defaultDeploymentRepo":"petclinic-docker-local"'

echo "Done. Maven: $JFROG_URL/artifactory/petclinic-maven  Docker: ${JFROG_URL#https://}/petclinic-docker"
