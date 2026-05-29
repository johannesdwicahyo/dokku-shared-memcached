# dokku-shared-memcached

[![CI](https://github.com/johannesdwicahyo/dokku-shared-memcached/actions/workflows/ci.yml/badge.svg)](https://github.com/johannesdwicahyo/dokku-shared-memcached/actions/workflows/ci.yml)

A [Dokku](https://dokku.com) plugin that runs **one shared Memcached container per host** and provisions tenants on it. Each tenant gets a key prefix; isolation is by **convention** (prefix discipline), not enforced access control — Memcached has no per-tenant auth. A periodic sweep flushes prefixes that exceed their byte quota.

Companion to [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres) and [dokku-shared-redis](https://github.com/johannesdwicahyo/dokku-shared-redis). Powers [wokku.cloud](https://wokku.cloud)'s free Memcached tier.

## ⚠️ Security model — read this first

Memcached has **no ACLs, no namespacing, and no per-tenant authentication**. This plugin gives each tenant a key prefix (`<name>:`) and trusts apps to stay inside it. A buggy or malicious app **can read another tenant's keys by guessing their prefix.**

**This is best-effort shared cache. Do not store secrets, tokens, PII, or anything you couldn't tolerate another tenant reading.** Treat it like a public scratch space that happens to be fast. If you need isolation guarantees, provision a dedicated cache.

## Install

```bash
dokku plugin:install https://github.com/johannesdwicahyo/dokku-shared-memcached.git
```

The install hook pulls `memcached:alpine`, starts the shared container (`memcached -m 256`), sets up `/etc/cron.d/dokku-shared-memcached` for the periodic quota sweep, and chowns the plugin data dir to `dokku:dokku`.

## Quick start

```bash
# Register a tenant. Prints the URL + required key prefix.
dokku shared-memcached:create my-cache
# -> MEMCACHED_URL=dokku-shared-memcached:11211
# -> MEMCACHED_KEY_PREFIX=my-cache:

# Wire it into an app (sets MEMCACHED_URL + MEMCACHED_KEY_PREFIX).
dokku shared-memcached:link my-cache my-app

# Inspect.
dokku shared-memcached:info my-cache
dokku shared-memcached:list

# Cap usage. Default is 25 MB per tenant.
dokku shared-memcached:set-quota my-cache 50

# Admin shell on the shared instance (sees ALL tenants — ops only).
dokku shared-memcached:connect my-cache

# Tear down (flushes the prefix).
dokku shared-memcached:unlink my-cache my-app
dokku shared-memcached:destroy my-cache -f
```

## The prefix gotcha

`link` sets two env vars on your app:

- `MEMCACHED_URL=dokku-shared-memcached:11211`
- `MEMCACHED_KEY_PREFIX=my-cache:`

**Every key your app reads or writes MUST start with that prefix.** Unlike Redis ACLs, nothing *stops* you from writing un-prefixed keys — they'll just collide with other tenants. Most cache libraries support a namespace out of the box:

```ruby
# Rails + Dalli
config.cache_store = :mem_cache_store,
  ENV.fetch("MEMCACHED_URL"),
  { namespace: ENV.fetch("MEMCACHED_KEY_PREFIX") }
```

For `pymemcache` (Python), wrap the client in a `KeyPrefixClient`. For Symfony, configure a prefixed cache pool. For raw clients, prepend `ENV["MEMCACHED_KEY_PREFIX"]` to every key yourself.

## How tenancy works

- **One container per host.** Image: `memcached:alpine`, started `memcached -m 256` with a `--memory 256m` Docker cap. No persistence — Memcached is volatile by design.
- **A tenant is pure config.** `create` allocates a prefix and a link list under `/var/lib/dokku/services/shared-memcached/<name>/`; no Memcached state is provisioned (prefixes need none).
- **Container hostname** `dokku-shared-memcached` resolves from apps on the `dokku-shared-memcached` Docker network. The plugin talks to Memcached via `docker exec`, so the host needs no Memcached client tools.

## Quotas

One cap per tenant: **bytes (MB)**, default **25 MB**.

The cron job runs `dokku shared-memcached:check-quotas` every 5 minutes. It walks each tenant's prefix (`stats cachedump`), sums the bytes, and — because Memcached can't make a tenant read-only — **flushes the prefix** (`delete` loop) when it's over cap, printing a `flushed name=… bytes=… cap_bytes=…` line for alerting. Under cap, it's silent.

```bash
dokku shared-memcached:check-quotas   # run the sweep on demand
```

## Commands

```text
shared-memcached:create <name>                 Register a tenant (allocate prefix <name>:).
shared-memcached:destroy <name> -f             Flush the prefix and drop tenant config.
shared-memcached:link <name> <app>             Set MEMCACHED_URL + MEMCACHED_KEY_PREFIX on <app>.
shared-memcached:unlink <name> <app>           Remove those vars from <app>.
shared-memcached:list                          All tenants on this host.
shared-memcached:info <name>                   Prefix, key/byte usage, quota, linked apps.
shared-memcached:connect <name>                Admin nc session to the shared memcached.
shared-memcached:set-quota <name> <mb>         Set the per-tenant byte cap.
shared-memcached:unset-quota <name>            Revert to the default cap.
shared-memcached:check-quotas                  Run the quota sweep manually.
shared-memcached:export <name>                 [stretch goal — not in v0.1.0]
shared-memcached:import <name>                 [stretch goal — not in v0.1.0]
shared-memcached:help                          Show usage.
```

## When NOT to use this

- You need isolation guarantees, auth, or to store anything sensitive. Use a dedicated cache.
- You need persistence, replication, or HA. Memcached here is volatile and single-node.
- You need >100 MB per tenant. Provision a dedicated instance instead.

## Development

```bash
make lint   # shellcheck -x
make test   # bats tests
```

Integration smoke (run on a real Dokku host):

```bash
ssh root@my-dokku-host 'bash -s' < tests/integration_smoke.sh
```

## License

MIT — see `LICENSE`.
