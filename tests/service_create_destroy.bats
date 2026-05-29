#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  # Pretend the container is already running so ensure_shared_container short-circuits.
  stub_response docker 'dokku-shared-memcached'
}

@test "service_create writes metadata files and provisions no memcached state" {
  service_create "demo"
  [[ -d "$PLUGIN_DATA_ROOT/demo" ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/LINKS" ]]
  # No password is generated — memcached has no per-tenant auth.
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/PASSWORD" ]]
}

@test "service_create refuses an existing tenant" {
  service_create "demo"
  run service_create "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"already exists"* ]]
}

@test "service_create rejects invalid name" {
  run service_create "BadName"
  [[ "$status" -ne 0 ]]
  run service_create ""
  [[ "$status" -ne 0 ]]
  run service_create "with spaces"
  [[ "$status" -ne 0 ]]
}

@test "service_url is the container host:port" {
  run service_url
  [[ "$status" -eq 0 ]]
  [[ "$output" == "dokku-shared-memcached:11211" ]]
}

@test "service_destroy purges the prefix then removes the data dir" {
  service_create "demo"
  : >"$STUB_LOG"
  # tenant_scan -> one cachedump payload returning two demo: keys; then the
  # batched delete call.
  stub_response docker $'ITEM demo:a [10 b; 0 s]\r\nITEM demo:b [20 b; 0 s]\r\nEND'
  stub_response docker ''
  service_destroy "demo"
  [[ ! -d "$PLUGIN_DATA_ROOT/demo" ]]
  # The delete batch was piped in on stdin and targets both demo keys.
  run grep -c 'docker-stdin .*delete demo:a' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
  run grep -c 'docker-stdin .*delete demo:b' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_destroy errors when tenant is missing" {
  run service_destroy "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}
