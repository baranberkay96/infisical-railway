# Infisical v0.166 Secrets Manager — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Infisical v0.166 Secrets Manager** (version label `v0.166` = major.minor of a 0.x release; Infisical tags `v0.x.y`) |
| Description | Store, sync and rotate secrets for your apps and teams. Self-hosted. (68 chars, unchanged from LISTINGS_ROUND2.md) |
| Category | Other |
| Tags | infisical, secrets-management, vault-alternative, devops, security, postgres, redis |
| User input at deploy | **`INFISICAL_ADMIN_EMAIL`** (super-admin). Everything else is generated. Optional later: SMTP, Google/GitHub sign-in. |

## Base market template

- **`infisical` "Infisical (Open-Source Secrets Management & Env Vault)"** (63 active / 44 recent projects) — chosen as base: Railway Postgres + Redis + Infisical with the minimal upstream variables. Kept: service split, `SITE_URL` from the public domain, SMTP variable set.
  Fixed: `infisical/infisical:latest-postgres` (that tag stopped updating in August 2025 at v0.146 — the template silently deploys a 14-month-old release), `ENCRYPTION_KEY=${{secret(32)}}` (alphanumeric, not the documented hex format), public TCP proxies on Postgres and Redis, no healthcheck, no migration step, unnamed image service, first visitor becomes super-admin.
- `CZTj7E` (31 active) — same `latest-postgres` tag, `bitnami/redis` running as root, public DB/Redis URLs. Nothing taken.
- `infisical-secrets-manager` (18 active) — `latest`, same key format. Nothing taken.
- No `_upstream` repos exist for this app. Market templates carry no license → reference only.

## Pinned versions

| Service | Image / source | Tag | Release date | Checked |
|---|---|---|---|---|
| Infisical | `infisical/infisical` | `v0.166.3` (= `latest`, digest `sha256:c063089e4525…`) | 2026-10-08 | 2026-10-11 |
| Infisical Bootstrap | `services/bootstrap` → `FROM curlimages/curl` | `8.22.0` | 2026-09-02 | 2026-10-11 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | Railway base | 2026-10-11 |
| Redis | `redis` | `8.2` | Railway base | 2026-10-11 |

The separate `-postgres` image variant no longer exists (last tag `v0.146.0-postgres`, 2025-08-07); the main image is Postgres-only. **Upgrade:** change the tag, back up Postgres, redeploy; the pre-deploy step migrates before the new version starts. Infisical ships near-daily patch releases — bump within the `v0.166` line freely, and rename the listing when moving to a new minor.

## Architecture

```
Browser / CLI / SDKs / K8s operator ──HTTPS──▶ Infisical (Fastify API + web UI, :8080 on [::], public)
                                                 │  pre-deploy: npm run migration:latest (retries while Postgres starts)
                                                 ├─▶ Postgres 18 (secrets, audit logs; encrypted with ENCRYPTION_KEY)
                                                 └─▶ Redis 8.2  (cache, BullMQ queues, rate limits; noeviction)
Infisical Bootstrap (one-shot) ──private──▶ POST /api/v1/admin/bootstrap  (super-admin + first organization)
```

### Deviations from upstream (and why)

- **Migrations in pre-deploy.** Infisical also migrates at start-up (with a Postgres lock); running `npm run migration:latest` first means a failed migration stops the deploy while the previous version keeps serving. Verified locally: pre-deploy applied 566 migrations; the app then logged `No migrations pending: Skipping migration process.`
- **`HOST=::`.** The image defaults to `0.0.0.0` (IPv4). Fastify on `::` is dual-stack (verified: listening on `[::]:8080`), so the bootstrap job reaches it in IPv6-only legacy environments; Railway's IPv4 healthcheck still works.
- **Admin bootstrap.** A fresh instance lets the first visitor create the super-admin. The `Infisical Bootstrap` job calls Infisical's documented instance-bootstrap API (`POST /api/v1/admin/bootstrap`, the endpoint behind `infisical bootstrap`) as soon as the server is healthy, creating the admin and the first organization; the machine-identity token in the response is discarded. Verified locally: HTTP 200 on a fresh instance, sign-in with the generated password works, a second run exits 0 with `already been set up`, and public sign-up is off afterwards (`allowSignUp: false`).
- **Redis `noeviction`** — Infisical runs BullMQ queues on Redis.
- **Telemetry off by default** (`TELEMETRY_ENABLED=false`; upstream default is on).

## Key formats (verified in `backend/src/lib/config/env.ts` and `lib/crypto/cryptography/crypto.ts`, v0.166.3)

- `ENCRYPTION_KEY`: upstream generates it with `openssl rand -hex 16` → **32 hex characters**, used as the AES-256 root key material. The template uses `${{secret(32, "0123456789abcdef")}}`. (FIPS mode instead requires a base64 256-bit key — not enabled here.)
- `AUTH_SECRET`: upstream uses `openssl rand -base64 32` (44 characters); it is used as the JWT signing secret string. The template generates 44 characters from the base64 alphabet.

## Services

All services are created together from the template; references resolve at deploy time. Empty values are optional.

### Infisical

- **Source:** Docker image `infisical/infisical:v0.166.3`
- **Start command:** image default
- **Pre-deploy command:** `/bin/sh -c "i=1; until npm run migration:latest; do if [ $i -ge 30 ]; then echo 'migrations failed 30 times'; exit 1; fi; i=$((i+1)); echo 'retrying migrations in 10s'; sleep 10; done"` (timeout 900 s)
- **Healthcheck:** `/api/status` (timeout 600 s)
- **Public domain:** yes → target port `8080`
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Port Infisical listens on; Railway routes traffic and healthchecks here. |
| `HOST` | `::` | Bind address. :: is dual-stack, so the bootstrap job reaches Infisical in IPv6-only private networks too. |
| `NODE_ENV` | `production` | Runtime mode. |
| `SITE_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Absolute public URL (links in e-mails, OAuth/SAML callbacks). Change it when you add a custom domain. |
| `ENCRYPTION_KEY` | `${{secret(32, "0123456789abcdef")}}` | Root key for platform encryption: 16 random bytes as 32 hex characters (upstream: openssl rand -hex 16). Back it up; without it stored secrets cannot be decrypted. Never change it without Infisical's key-rotation procedure. |
| `AUTH_SECRET` | `${{secret(44, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")}}` | Signs JWT sessions: 44 base64 characters (~32 bytes, upstream: openssl rand -base64 32). Changing it signs everyone out. |
| `DB_CONNECTION_URI` | `${{Postgres.DATABASE_URL}}` | Postgres connection string (private network). |
| `REDIS_URL` | `${{Redis.REDIS_URL}}?family=0` | Redis for cache and job queues. family=0 lets ioredis use IPv4 or IPv6 on the private network. |
| `TELEMETRY_ENABLED` | `false` | Anonymous usage telemetry to Infisical. Off by default in this template; set true to share it. |
| `SMTP_HOST` | *(empty)* | SMTP host for invitations, MFA codes and alerts (Infisical supports SMTP only; outbound SMTP needs Railway Pro). Optional. |
| `SMTP_PORT` | `587` | SMTP port (587 STARTTLS, 465 TLS). |
| `SMTP_USERNAME` | *(empty)* | SMTP username. Optional. |
| `SMTP_PASSWORD` | *(empty)* | SMTP password. Optional. |
| `SMTP_FROM_ADDRESS` | *(empty)* | Sender address, e.g. infisical@yourcompany.com. Optional. |
| `SMTP_FROM_NAME` | `Infisical` | Sender display name. |
| `CLIENT_ID_GOOGLE_LOGIN` | *(empty)* | Optional Google OAuth client ID for 'Continue with Google' (redirect: SITE_URL/api/v1/sso/google). |
| `CLIENT_SECRET_GOOGLE_LOGIN` | *(empty)* | Optional Google OAuth client secret. |
| `CLIENT_ID_GITHUB_LOGIN` | *(empty)* | Optional GitHub OAuth app client ID for 'Continue with GitHub' (callback: SITE_URL/api/v1/sso/github). |
| `CLIENT_SECRET_GITHUB_LOGIN` | *(empty)* | Optional GitHub OAuth app client secret. |

### Postgres

- **Source:** Docker image `ghcr.io/railwayapp-templates/postgres-ssl:18`
- **Start command:** image default
- **Healthcheck:** none
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/var/lib/postgresql/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized. |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| `PGPORT` | `5432` | Port to connect to Postgres. |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for Data panel. |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel. |
| `POSTGRES_DB` | `railway` | Default database created when image is started. |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | URL to connect to Postgres database. |
| `POSTGRES_USER` | `postgres` | User to connect to Postgres DB. |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Password to connect to DB. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to cleanly shut down. |

### Redis

- **Source:** Docker image `redis:8.2`
- **Start command:** `/bin/sh -c "rm -rf $RAILWAY_VOLUME_MOUNT_PATH/lost+found/ && exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save 60 1 --dir $RAILWAY_VOLUME_MOUNT_PATH --maxmemory-policy noeviction"`
- **Healthcheck:** none
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname of the Redis service, only resolvable from services in the same environment. |
| `REDISPORT` | `6379` | Port that Redis listens on. |
| `REDISUSER` | `default` | Username for authenticating with Redis. |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string for connecting to Redis using the private network. |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name. |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis. |

### Infisical Bootstrap

- **Source:** repo `baranberkay96/infisical-railway`, root directory `/services/bootstrap` (Dockerfile build)
- **Start command:** image default
- **Healthcheck:** none
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `INFISICAL_INTERNAL_URL` | `http://${{Infisical.RAILWAY_PRIVATE_DOMAIN}}:8080` | Infisical's private address. |
| `INFISICAL_ADMIN_EMAIL` | *(empty)* | E-mail of the super-admin account this job creates right after the first boot (closes the 'first visitor becomes admin' window). **Required input.** |
| `INFISICAL_ADMIN_PASSWORD` | `${{secret(32)}}` | Password of the super-admin (letters and digits). Read it here for the first sign-in, then change it in Infisical. |
| `INFISICAL_ORGANIZATION_NAME` | `My Organization` | Name of the first organization. |
| `BOOTSTRAP_WAIT_SECONDS` | `1200` | How long the job waits for Infisical to come up. |


## Improvements over market templates

| # | Change | Why |
|---|---|---|
| 1 | Pinned `v0.166.3` (leader: `latest-postgres`, frozen since v0.146) | Current release, reproducible deploys. |
| 2 | `ENCRYPTION_KEY` in the documented 32-hex format, `AUTH_SECRET` in base64 length | Matches upstream generation commands. |
| 3 | Migrations in pre-deploy with retries | Safe upgrades; no race with Postgres on a cold deploy. |
| 4 | Super-admin created by a one-shot bootstrap job | Closes the "first visitor becomes admin" window on a secrets manager. |
| 5 | Healthcheck `/api/status`, `HOST=::` | Railway routes only to healthy deployments; works on IPv6-only private networks. |
| 6 | No public TCP proxies on Postgres/Redis; Redis `noeviction`; `?family=0` on the Redis URL | Smaller attack surface; queue-safe Redis; dual-stack client. |
| 7 | SMTP + Google/GitHub sign-in variables with descriptions | Mail and SSO are a form away. |

## First login

1. Wait for **Infisical Bootstrap** to log `Instance bootstrapped: super-admin …`.
2. Open the public URL and sign in with `INFISICAL_ADMIN_EMAIL` and the `INFISICAL_ADMIN_PASSWORD` value from the Infisical Bootstrap service variables. Change the password (Personal Settings) and enable MFA.
3. Server Admin Console (`/admin`): public sign-up is disabled after bootstrap; invite colleagues from Organization → Access Control, or allow sign-ups for your e-mail domain.
4. **Back up `ENCRYPTION_KEY`** (Infisical service variables) somewhere outside Railway. Database backups are useless without it.
5. E-mail: Infisical sends invitations and MFA codes over SMTP only. On Railway Hobby (no outbound SMTP), use invitation links shown in the UI, or move to Pro and fill the `SMTP_*` variables.

## Scaling

- **Infisical:** stateless (no volume). Raise replicas for API load; migrations stay single-run in pre-deploy and the start-up migrator is lock-protected.
- **Postgres:** vertical; HA conversion available. **Redis:** small; vertical if needed.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Idle figures measured locally (2026-10-11).

| Service | Idle RAM | Idle CPU | Typical RAM | Typical CPU |
|---|---|---|---|---|
| Infisical | 670–850 MB | 0.02 vCPU | 1.0 GB | 0.12 vCPU |
| Postgres | 150–200 MB | 0.01 vCPU | 300 MB | 0.03 vCPU |
| Redis | 10 MB | <0.01 vCPU | 30 MB | 0.01 vCPU |
| Infisical Bootstrap | 0 (exits) | 0 | 0 | 0 |
| **Total** | **≈1.0 GB** | **≈0.03 vCPU** | **≈1.35 GB** | **≈0.16 vCPU** |

- **Idle:** ≈ $10 RAM + $0.6 CPU + $0.2 volumes ≈ **$11/month**.
- **Typical (team of 20, CI/CD pulling secrets):** ≈ $13.5 RAM + $3.2 CPU + $0.3 volumes ≈ **$17/month**.
- **Minimum plan:** Hobby. The Infisical service runs close to Trial's 1 GB/service limit at idle (`NODE_OPTIONS=--max-old-space-size=2048` in the image).

## Verification checklist

- [ ] **Infisical** pre-deploy log shows `Batch 1 run: … migrations` (first deploy) and ends successfully; deployment healthy on `/api/status` (`"message":"Ok"`, `"redisConfigured":true`).
- [ ] **Infisical Bootstrap** logs `Instance bootstrapped` and exits 0 (later redeploys: `already been set up`).
- [ ] Sign in as the admin; create a project, add a secret, read it back with the Infisical CLI (`infisical login --domain https://{your-domain}`).
- [ ] Redeploy Infisical: secrets still readable (proves `ENCRYPTION_KEY` and Postgres persistence).
- [ ] `/admin` → General: sign-ups disabled.

## Open questions

- **SMTP on Hobby:** Infisical has no HTTP mail provider; invitation/MFA e-mails need Railway Pro or an SMTP relay on a non-blocked port. Not testable locally.
- **AUTH_SECRET alphabet:** generated from the base64 alphabet without `=` padding; Infisical uses the value as an HMAC secret string, so any 44-character value is accepted (verified by signing in locally).
- **Bootstrap response token:** the bootstrap API also creates a machine identity with a token. The job discards it; admins create their own identities in the UI.
