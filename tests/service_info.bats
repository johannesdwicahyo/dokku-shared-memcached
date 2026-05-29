#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
}

@test "service_info prints all fields including quota default" {
  # tenant_scan -> one metadump payload with two demo keys (10 + 22 bytes).
  # `demo%3Aa` is the URL-encoded form of `demo:a` (`%3A` = `:`).
  stub_response docker $'key=demo%3Aa exp=-1 la=0 cas=1 fetch=no cls=1 size=10 flags=0\nkey=demo%3Ab exp=-1 la=0 cas=2 fetch=no cls=1 size=22 flags=0\nEND'
  run service_info "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"name=demo"* ]]
  [[ "$output" == *"key_prefix=demo:"* ]]
  [[ "$output" == *"host=dokku-shared-memcached"* ]]
  [[ "$output" == *"port=11211"* ]]
  [[ "$output" == *"keys=2"* ]]
  [[ "$output" == *"memory_bytes=32"* ]]
  [[ "$output" == *"quota_mb=25"* ]]
}

@test "service_info reports zero usage when the prefix is empty" {
  stub_response docker $'END'
  run service_info "demo"
  [[ "$output" == *"keys=0"* ]]
  [[ "$output" == *"memory_bytes=0"* ]]
}

@test "service_info reports linked apps as csv" {
  printf 'app1\napp2\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  stub_response docker $'END'
  run service_info "demo"
  [[ "$output" == *"linked_apps=app1,app2"* ]]
}

@test "service_info errors when tenant is missing" {
  run service_info "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "service_list lists tenants alphabetically and skips _internal" {
  mkdir -p "$PLUGIN_DATA_ROOT/zeta" "$PLUGIN_DATA_ROOT/alpha" "$PLUGIN_DATA_ROOT/_internal"
  run service_list
  [[ "$status" -eq 0 ]]
  lines=()
  while IFS= read -r l; do lines+=("$l"); done <<< "$output"
  [[ "${lines[0]}" == "alpha" ]]
  [[ "${lines[1]}" == "demo" ]]
  [[ "${lines[2]}" == "zeta" ]]
  for l in "${lines[@]}"; do
    [[ "$l" != "_internal" ]] || { echo "_internal leaked into list"; return 1; }
  done
}
