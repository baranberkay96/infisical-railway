# NOTICE — Infisical v0.166 Secrets Manager

## Software deployed (not redistributed)

| Component | Source | License |
|---|---|---|
| Infisical | Docker image `infisical/infisical:v0.166.3` from https://github.com/Infisical/infisical | MIT (Expat) for the core; content under `ee/` directories is under Infisical's enterprise license (repository `LICENSE`) |
| curl | `curlimages/curl:8.22.0` (base of `services/bootstrap`) | curl license (MIT-style) |
| PostgreSQL | Railway base image `ghcr.io/railwayapp-templates/postgres-ssl:18` | PostgreSQL License |
| Redis | `redis:8.2` (Railway base definition) | Redis 8 tri-license (RSALv2 / SSPLv1 / AGPLv3) |

The template references these images; it does not modify their code. `services/bootstrap/Dockerfile` and `bootstrap.sh` are original work for this template (structure follows this project's round-1 Windmill bootstrap job).

## Upstream files checked (2026-10-11, tag `v0.166.3`)

- `Dockerfile.standalone-infisical`, `standalone-entrypoint.sh` — port 8080, `HOST=0.0.0.0` default, non-root user, start command.
- `docker-compose.prod.yml`, `.env.example` — services and required variables.
- `backend/src/lib/config/env.ts` — variable schema (`HOST`, `ENCRYPTION_KEY`, `AUTH_SECRET`, `REDIS_URL` requirement, SMTP, telemetry).
- `backend/src/lib/crypto/cryptography/crypto.ts` — key handling (hex key in normal mode, base64 256-bit only in FIPS mode).
- `backend/src/main.ts`, `backend/src/auto-start-migrations.ts`, `backend/package.json` — start-up migrations with locks, `migration:latest` script.
- `backend/src/server/routes/v1/admin-router.ts` (`/bootstrap`, `/config`), `v3/login-router.ts`, `v1/sso-router.ts` — bootstrap API, login, OAuth callback paths.
- Docs: `docs/self-hosting/deployment-options/standalone-infisical.mdx`, `gcp-native.mdx` (`openssl rand -hex 16`, `openssl rand -base64 32`, `npm run migration:latest`).
- Docker Hub tag list (`-postgres` variant last published 2025-08-07).

## Reused material

- **Railway base definitions** `templates/_railway-base/postgres.json` and `redis.json` (this repository): copied as instructed by STANDARD.md; `--maxmemory-policy noeviction` appended to the Redis start command.
- **Market templates** `infisical`, `CZTj7E`, `infisical-secrets-manager` (Railway marketplace, no license): reviewed for structure only; no text or files copied. All prose in this package is original.
- No `_upstream` repositories exist for this app.
