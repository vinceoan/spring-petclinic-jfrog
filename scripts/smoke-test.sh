#!/usr/bin/env bash
# Start the image, wait for its HEALTHCHECK, then request a few URLs from inside
# the container.
#
#   scripts/smoke-test.sh <image>
set -euo pipefail

image=${1:?usage: smoke-test.sh <image>}
name=petclinic-smoke-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

docker run --detach --name "$name" "$image" >/dev/null
for _ in $(seq 1 60); do
  state=$(docker inspect -f '{{.State.Status}}/{{.State.Health.Status}}' "$name")
  [[ $state == running/starting ]] || break
  sleep 3
done
if [[ $state != running/healthy ]]; then
  docker logs --tail 50 "$name" >&2
  echo "FAIL: container is $state" >&2
  exit 1
fi

docker exec "$name" curl -fsS http://localhost:8080/actuator/health | grep -q '"status":"UP"' ||
  { echo "FAIL: /actuator/health is not UP" >&2; exit 1; }
for path in / /vets.html; do
  docker exec "$name" curl -fsS -o /dev/null "http://localhost:8080$path"
done
echo "Smoke test passed: $image"
