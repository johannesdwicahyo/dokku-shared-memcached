#!/usr/bin/env bats
load test_helper

# Verifies every subcommand accepts the Dokku 0.38 invocation convention:
# $1 is "shared-memcached:<cmd>" and user args start at $2. Each script
# `shift`s that prefix off before reading positional args.

setup() {
  setup_plugin_env
}

@test "create rejects empty name and points at the right cmd" {
  run "$REPO_ROOT/subcommands/create" "shared-memcached:create"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"shared-memcached:create"* ]]
}

@test "destroy requires -f and treats positional 1 as the tenant name" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  run "$REPO_ROOT/subcommands/destroy" "shared-memcached:destroy" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"refusing to destroy"* ]]
}

@test "list runs cleanly with no tenants" {
  run "$REPO_ROOT/subcommands/list" "shared-memcached:list"
  [[ "$status" -eq 0 ]]
}

@test "set-quota parses the positional mb arg" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  run "$REPO_ROOT/subcommands/set-quota" "shared-memcached:set-quota" "demo" "50"
  [[ "$status" -eq 0 ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MB")" == "50" ]]
}

@test "info errors when tenant is missing" {
  run "$REPO_ROOT/subcommands/info" "shared-memcached:info" "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "export errors with stretch-goal message and non-zero exit" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  run "$REPO_ROOT/subcommands/export" "shared-memcached:export" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"v0.2 stretch goal"* ]]
}

@test "commands dispatcher routes unknown subcommand to error" {
  run "$REPO_ROOT/commands" "shared-memcached:does-not-exist"
  [[ "$status" -ne 0 ]]
}
