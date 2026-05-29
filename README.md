# dokku-shared-memcached

Shared, multi-tenant Memcached plugin for Dokku. One Memcached container
per host; per-tenant isolation via **enforced key-prefix discipline**.
Plugin-level quota enforcement on bytes used per prefix.

**Status:** scaffolded 2026-05-30. v0.1.0 not yet built. See `CLAUDE.md`
for the complete onboarding brief.

## Why

Companion to:

- [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres)
- [dokku-shared-redis](https://github.com/johannesdwicahyo/dokku-shared-redis)
- [dokku-shared-minio](https://github.com/johannesdwicahyo/dokku-shared-minio)

Backs the every-box-includes-Memcached tier in
[Wokku Cloud](https://wokku.cloud) plans (bundle v2).

## Security note

Memcached has no native ACL or key namespacing. Tenants are isolated by
**enforced prefix discipline** at the app library layer
(`MEMCACHED_KEY_PREFIX` env var) — but a buggy or malicious tenant CAN
read other tenants' keys by guessing prefixes.

**Do not store secrets, tokens, or PII in shared Memcached.** Use it for
ephemeral cache only.

## License

MIT (target).
