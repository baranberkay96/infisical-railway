# Deploy and Host Infisical with Railway

Infisical is an open-source secrets manager: store environment variables, API keys and certificates per project and environment, sync them to your apps and CI/CD, and keep an audit trail of every access. This community template runs Infisical on Railway with Postgres and Redis, generated keys, and an admin account created for you.

## About Hosting Infisical

Infisical is a single Node.js service that serves the web UI and the API used by its CLI, SDKs and Kubernetes operator. It needs Postgres for encrypted secrets and audit logs, Redis for caching and job queues, a root encryption key, and a JWT signing secret. This template pins a current release, generates both keys in the formats upstream documents, runs database migrations as a pre-deploy step, binds the server dual-stack on Railway's private network, and runs a one-shot job that claims the instance with your admin e-mail, so nobody else can register as super-admin before you open the URL.

## Common Use Cases

- Replacing `.env` files shared over chat with per-environment secrets and access control
- Injecting secrets into Railway services, Docker builds and CI pipelines with the Infisical CLI
- Syncing secrets to cloud providers and Kubernetes through Infisical integrations
- Auditing who read or changed which secret, and rotating credentials on a schedule

## Dependencies for Infisical Hosting

- Infisical (`infisical/infisical:v0.166.3`)
- PostgreSQL (Railway Postgres 18)
- Redis (cache and queues)
- Optional: an SMTP server for invitation and MFA e-mails (Railway Pro)

### Deployment Dependencies

- Infisical self-hosting overview: https://infisical.com/docs/self-hosting/overview
- Environment variable reference: https://infisical.com/docs/self-hosting/configuration/envars
- Instance bootstrap API: https://infisical.com/docs/self-hosting/guides/automated-bootstrapping
- Infisical source and releases: https://github.com/Infisical/infisical

### Implementation Details

| Service | Image / source | Role |
|---|---|---|
| Infisical | `infisical/infisical:v0.166.3` | Web UI and API on the public domain; migrations in pre-deploy |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl:18` | Encrypted secrets, audit logs (volume) |
| Redis | `redis:8.2` | Cache and job queues (volume, `noeviction`) |
| Infisical Bootstrap | `services/bootstrap` (curl) | One-shot job: creates the super-admin and first organization |

**First login:** enter your e-mail in `INFISICAL_ADMIN_EMAIL` when deploying. When the Infisical Bootstrap service logs "Instance bootstrapped", sign in at `https://{your-domain}` with that e-mail and the `INFISICAL_ADMIN_PASSWORD` value from the Infisical Bootstrap variables, then change the password and enable MFA. Public sign-up is closed after bootstrap; invite your team from the organization settings.

**Back up the encryption key:** copy `ENCRYPTION_KEY` from the Infisical service variables to a safe place outside Railway. Without it, a database backup cannot be decrypted.

**E-mail:** Infisical sends mail over SMTP only. Railway allows outbound SMTP on the Pro plan; on other plans, share the invitation links shown in the UI.

**Scaling:** Infisical keeps no local state, so you can add replicas for API-heavy workloads such as many CI jobs. Scale Postgres vertically.

**Versions:** change the image tag on the Infisical service and redeploy; migrations run in the pre-deploy step, and a failed migration leaves the running version untouched. Back up Postgres before upgrading.

### Why Deploy Infisical on Railway?

Railway runs Infisical, its database and cache on a private network with managed volumes and usage-based billing, and your Railway services can pull secrets from it over that network. You get a self-hosted secrets manager under your own control without operating servers.
