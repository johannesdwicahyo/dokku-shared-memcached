#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
}

@test "subcommands/help prints usage with all subcommands" {
  run "$REPO_ROOT/subcommands/help" "shared-memcached:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-memcached:"* ]]
  for cmd in create destroy link unlink list info connect set-quota unset-quota check-quotas export import help; do
    [[ "$output" == *"shared-memcached:$cmd"* ]] || {
      echo "missing command in help output: $cmd"
      return 1
    }
  done
}

@test "commands dispatcher routes :help to subcommands/help" {
  run "$REPO_ROOT/commands" "shared-memcached:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-memcached:"* ]]
}

@test "help carries the prefix-discipline + security warning" {
  run "$REPO_ROOT/subcommands/help" "shared-memcached:help"
  [[ "$output" == *"MEMCACHED_KEY_PREFIX"* ]]
  [[ "$output" == *"Do not store secrets"* ]]
}
