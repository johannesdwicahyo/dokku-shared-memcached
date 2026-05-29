#!/usr/bin/env bash
#
# Integration smoke for shared-memcached. Run on a real Dokku host after
# installing the plugin. Not invoked by CI.
#
# Usage:
#   ssh root@my-dokku-host 'bash -s' < tests/integration_smoke.sh

set -euo pipefail

TENANT="${TENANT:-smoke$(date +%s)}"
TENANT2="${TENANT2:-smoke$(date +%s)b}"
APP="${APP:-smokeapp$(date +%s)}"
C="dokku-shared-memcached"
PORT="11211"

step() { printf '\n=== %s ===\n' "$1"; }

# Send a memcached text-protocol command to the shared container, echo reply.
mc() { printf '%s\r\nquit\r\n' "$1" | docker exec -i "$C" nc -w 2 127.0.0.1 "$PORT"; }

cleanup() {
  set +e
  step "cleanup"
  sudo -u dokku dokku apps:destroy "$APP" --force 2>/dev/null || true
  sudo -u dokku dokku shared-memcached:destroy "$TENANT" -f  2>/dev/null || true
  sudo -u dokku dokku shared-memcached:destroy "$TENANT2" -f 2>/dev/null || true
}
trap cleanup EXIT

step "1. plugin installed and dispatcher responds"
sudo -u dokku dokku shared-memcached:help | grep -q "create <name>" \
  || { echo "FAIL: :help output missing 'create <name>'"; exit 1; }

step "2. data dir is dokku-owned"
# shellcheck disable=SC2012  # fixed admin path; ls output is just informational
ls -ld /var/lib/dokku/services/shared-memcached | awk '{print "  perm/owner:", $1, $3, $4}'
[[ "$(stat -c '%U:%G' /var/lib/dokku/services/shared-memcached)" == "dokku:dokku" ]] \
  || { echo "FAIL: data dir not owned by dokku:dokku"; exit 1; }

step "3. shared container is up and reachable"
docker ps --filter "name=^${C}$" --format '{{.Names}} {{.Status}}' | grep -q "$C" \
  || { echo "FAIL: shared container not running"; exit 1; }
mc 'version' | grep -qi 'VERSION' || { echo "FAIL: memcached did not answer 'version'"; exit 1; }

step "4. create tenant '$TENANT'"
sudo -u dokku dokku shared-memcached:create "$TENANT" | tee /tmp/.smoke-create
grep -q "MEMCACHED_KEY_PREFIX=${TENANT}:" /tmp/.smoke-create \
  || { echo "FAIL: create didn't print the key prefix"; exit 1; }

step "5. info reports the tenant"
sudo -u dokku dokku shared-memcached:info "$TENANT" | tee /tmp/.smoke-info
grep -q "Name:.*$TENANT"          /tmp/.smoke-info || { echo "FAIL: info missing Name"; exit 1; }
grep -q "Key prefix:.*${TENANT}:" /tmp/.smoke-info || { echo "FAIL: info missing Key prefix"; exit 1; }

step "6. write some prefixed keys; info counts them"
mc "set ${TENANT}:hello 0 0 5
world" >/dev/null
mc "set ${TENANT}:hi 0 0 2
yo" >/dev/null
sudo -u dokku dokku shared-memcached:info "$TENANT" | grep -q "Keys:.*2" \
  || { echo "FAIL: info did not count 2 keys"; exit 1; }

step "7. prefix scan isolation: tenant2's prefix sees none of tenant1's keys"
sudo -u dokku dokku shared-memcached:create "$TENANT2" >/dev/null
sudo -u dokku dokku shared-memcached:info "$TENANT2" | grep -q "Keys:.*0" \
  || { echo "FAIL: tenant2 prefix scan is not empty"; exit 1; }

step "8. quota: tiny cap flushes the prefix on sweep"
sudo -u dokku dokku shared-memcached:set-quota "$TENANT" 0 2>/dev/null \
  && { echo "FAIL: set-quota accepted 0"; exit 1; } || true
# Set a 1 MB cap, then push the prefix over 1 MB. Memcached rejects
# single items > 1 MB by default (`SERVER_ERROR object too large for
# cache`), so write many smaller keys instead: 12 × 100 KB ≈ 1.2 MB of
# value data, comfortably over the 1 MB cap.
sudo -u dokku dokku shared-memcached:set-quota "$TENANT" 1
chunk="$(head -c 100000 </dev/zero | tr '\0' 'x')"
batch=""
for i in $(seq 1 12); do
  batch+="set ${TENANT}:k${i} 0 0 ${#chunk}"$'\r\n'"${chunk}"$'\r\n'
done
batch+="quit"$'\r\n'
printf '%s' "$batch" | docker exec -i "$C" nc -w 5 127.0.0.1 "$PORT" >/dev/null
sudo -u dokku dokku shared-memcached:check-quotas | tee /tmp/.smoke-sweep
grep -q "flushed name=$TENANT" /tmp/.smoke-sweep \
  || { echo "FAIL: sweep didn't flush over-cap tenant"; exit 1; }
sudo -u dokku dokku shared-memcached:info "$TENANT" | grep -q "Keys:.*0" \
  || { echo "FAIL: prefix not empty after flush"; exit 1; }

step "9. link to a Dokku app and verify both env vars"
sudo -u dokku dokku apps:create "$APP"
sudo -u dokku dokku shared-memcached:link "$TENANT" "$APP"
url="$(sudo -u dokku dokku config:get "$APP" MEMCACHED_URL)"
pfx="$(sudo -u dokku dokku config:get "$APP" MEMCACHED_KEY_PREFIX)"
[[ "$url" == "${C}:${PORT}" ]]   || { echo "FAIL: MEMCACHED_URL wrong: $url"; exit 1; }
[[ "$pfx" == "${TENANT}:" ]]     || { echo "FAIL: MEMCACHED_KEY_PREFIX wrong: $pfx"; exit 1; }
echo "  MEMCACHED_URL=$url  MEMCACHED_KEY_PREFIX=$pfx"

step "10. unlink removes both vars"
sudo -u dokku dokku shared-memcached:unlink "$TENANT" "$APP"
[[ -z "$(sudo -u dokku dokku config:get "$APP" MEMCACHED_URL || true)" ]] \
  || { echo "FAIL: MEMCACHED_URL still set after unlink"; exit 1; }
[[ -z "$(sudo -u dokku dokku config:get "$APP" MEMCACHED_KEY_PREFIX || true)" ]] \
  || { echo "FAIL: MEMCACHED_KEY_PREFIX still set after unlink"; exit 1; }

step "11. list shows the tenants"
sudo -u dokku dokku shared-memcached:list | grep -q "^$TENANT$" \
  || { echo "FAIL: list didn't include $TENANT"; exit 1; }

step "12. destroy and verify it's gone"
sudo -u dokku dokku shared-memcached:destroy "$TENANT" -f
sudo -u dokku dokku shared-memcached:destroy "$TENANT2" -f
sudo -u dokku dokku shared-memcached:list | grep -q "^$TENANT$" \
  && { echo "FAIL: tenant still in list after destroy"; exit 1; } || true

echo
echo "=== ALL SMOKE STEPS PASSED ==="
