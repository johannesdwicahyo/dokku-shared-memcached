#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
}

@test "service_get_quota_mb returns default when no override" {
  run service_get_quota_mb "demo"
  [[ "$output" == "25" ]]
}

@test "service_set_quota writes the override file" {
  service_set_quota "demo" "50"
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MB")" == "50" ]]
}

@test "service_set_quota rejects nothing-provided" {
  run service_set_quota "demo" ""
  [[ "$status" -ne 0 ]]
}

@test "service_set_quota rejects non-numeric / zero / negative" {
  run service_set_quota "demo" "huge"
  [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "0"
  [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "-5"
  [[ "$status" -ne 0 ]]
}

@test "service_unset_quota removes the override file" {
  printf '50' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  service_unset_quota "demo"
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_MB" ]]
}

@test "service_check_quota flushes the prefix when over the byte cap" {
  printf '1' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"   # 1 MB cap
  # First scan (usage) -> one key worth 2 MB, over cap.
  stub_response docker $'ITEM demo:big [2097152 b; 0 s]\r\nEND'
  # purge re-scans -> same key...
  stub_response docker $'ITEM demo:big [2097152 b; 0 s]\r\nEND'
  # ...then the batched delete.
  stub_response docker ''
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"flushed"* ]]
  [[ "$output" == *"name=demo"* ]]
  run grep -c 'docker-stdin .*delete demo:big' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_check_quota is silent and flushes nothing when under cap" {
  printf '10' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  stub_response docker $'ITEM demo:a [1024 b; 0 s]\r\nEND'
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  run grep -c 'docker-stdin .*delete' "$STUB_LOG"
  [[ "$output" == "0" ]]
}

@test "service_check_quota errors when tenant is missing" {
  run service_check_quota "ghost"
  [[ "$status" -ne 0 ]]
}
