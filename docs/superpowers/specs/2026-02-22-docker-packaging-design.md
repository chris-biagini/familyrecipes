# Docker Packaging Design

**Date:** 2026-02-22
**Status:** Approved

## Context

The familyrecipes Rails app is ready for homelab deployment. The target environment is "rika," an Ubuntu server already running Docker containers (Jellyfin, etc.) behind a reverse proxy. The goal is to build a Docker image via GitHub Actions, push it to GHCR, and pull it down to rika with docker-compose.

## Decisions

- **Registry:** GitHub Container Registry (`ghcr.io`)
- **CI/CD:** GitHub Actions auto-builds on push to `main`
- **Database:** PostgreSQL included in the docker-compose stack
- **TLS:** Terminated at rika's existing reverse proxy; Rails trusts forwarded headers
- **Compose location:** Example in repo (`docker-compose.example.yml`), real config lives on rika

## Dockerfile

Two-stage build on `ruby:3.2-slim` (Debian-based for native gem compatibility).

**Builder stage:**
- Installs `build-essential` and `libpq-dev`
- Copies `Gemfile` + `Gemfile.lock` first for layer caching
- Runs `bundle install --without development test`
- Copies full app source

**Runtime stage:**
- Fresh `ruby:3.2-slim` with only `libpq5` (runtime PostgreSQL client)
- Copies gems and app from builder
- Precompiles assets via `rails assets:precompile`
- Runs as non-root `rails` user
- Exposes port 3030

Expected image size: ~150–200MB.

## Entrypoint Script

`bin/docker-entrypoint` runs before Puma:

1. `rails db:prepare` — creates or migrates the database (idempotent)
2. `rails db:seed` — imports recipes and site documents (idempotent)
3. `exec "$@"` — hands off to Puma

Every deploy: pull new image, restart container, migrations and seeds happen automatically.

## GitHub Actions Workflow

`.github/workflows/docker.yml`, triggered on push to `main`:

1. Checkout repo
2. Log in to GHCR via built-in `GITHUB_TOKEN`
3. Set up Docker Buildx
4. Build and push with two tags:
   - `ghcr.io/<owner>/familyrecipes:latest`
   - `ghcr.io/<owner>/familyrecipes:<git-sha>` (immutable, for rollback)
5. Layer caching via GitHub Actions cache

On rika: `docker compose pull && docker compose up -d`.

## Docker Compose

`docker-compose.example.yml` in the repo; customized copy on rika.

**`db` service (PostgreSQL 16):**
- Named volume (`familyrecipes_pgdata`) for persistence
- Health check via `pg_isready`
- Credentials via environment variables

**`app` service (familyrecipes):**
- Pulls from `ghcr.io/<owner>/familyrecipes:latest`
- `depends_on` db with health check condition
- Exposes `127.0.0.1:3030:3030` (reverse proxy connects here)
- Environment: `DATABASE_HOST=db`, credentials, `SECRET_KEY_BASE`, `RAILS_ENV=production`
- Restart policy: `unless-stopped`

**Not included:** No reverse proxy (already exists), no Redis, no Sidekiq, no app volumes (stateless — all state in Postgres).

## Production Config

Minimal changes to existing Rails config:

- `force_ssl` + `assume_ssl` already set — Rails trusts `X-Forwarded-Proto` from the proxy
- `BINDING=0.0.0.0` default works for containers
- OmniAuth production providers are a separate future concern
- `SECRET_KEY_BASE` set via env var (generate with `rails secret`)

## .dockerignore

Excludes `.git`, `.env`, `tmp/`, `log/`, `test/`, `docs/`, `.claude/`, `.playwright-mcp/`, `node_modules/`, `*.png`. Keeps `db/seeds/` in the image for the entrypoint seed step.

## File Inventory

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage image build |
| `bin/docker-entrypoint` | DB setup + Puma startup |
| `.dockerignore` | Build context exclusions |
| `.github/workflows/docker.yml` | Auto-build on push to main |
| `docker-compose.example.yml` | Reference compose file for rika |
