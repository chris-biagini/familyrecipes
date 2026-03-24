# Docker Deployment & README Rewrite Design

**Date:** 2026-02-25

## Problem

The README is outdated (references PostgreSQL, has family-specific credits, missing Docker
install instructions). The `docker-compose.example.yml` references a PostgreSQL service that
doesn't exist — the app is SQLite-only. A first-time deployer would be confused.

## Goals

1. Rewrite README to describe the current feature set accurately
2. Provide clear Docker install instructions with Authelia + Caddy examples
3. Fix the stale `docker-compose.example.yml` (remove PostgreSQL references)
4. Document backup and update procedures
5. Make the README generic for open-source consumption

## Docker Gotchas Identified

### 1. Stale PostgreSQL references
The `docker-compose.example.yml` and README reference PostgreSQL. The app uses SQLite
(two databases: primary + cable, both in `/app/storage`). Fix: rewrite compose file.

### 2. force_ssl + assume_ssl behind Caddy
Production config has `force_ssl = true` and `assume_ssl = true`. Caddy must send
`X-Forwarded-Proto: https` (it does by default with `reverse_proxy`). Without a
TLS-terminating proxy, the app enters a redirect loop. Document this requirement.

### 3. SQLite WAL mode and Docker volumes
SQLite WAL creates `-wal` and `-shm` companion files. All must live on the same
filesystem (the Docker volume at `/app/storage`). The Dockerfile already seeds correct
ownership. Document: don't manually chmod the volume.

### 4. Seed data on updates
The entrypoint runs `db:seed` on every start. Seeds are idempotent and skip web-edited
recipes. New seed recipes from code updates get imported automatically. Document this
behavior.

## README Structure

1. **Header + tagline** — Generic description (self-hosted recipe manager)
2. **Features** — Organized by category (recipes, groceries, nutrition, kitchens, auth, deployment)
3. **Tech Stack** — Rails 8, SQLite, Solid Cable, Propshaft, Puma
4. **Quick Start (Docker)** — Primary install path with docker-compose
5. **Configuration** — Env vars table, Authelia + Caddy example snippets
6. **Backups** — SQLite volume backup procedure (stopped + live options)
7. **Updating** — Pull, restart, data preservation semantics
8. **Development** — Local dev setup for contributors
9. **Credits** — Generic (tools and inspiration)

## Feature Set to Document

**Recipe Management:** Markdown authoring, web editing, cross-references, categories,
scalable quantities, front matter (Category/Makes/Serves).

**Grocery Lists:** Build from recipes, real-time sync (ActionCable/Solid Cable),
aisle-grouped display, customizable aisle ordering, check-off, Quick Bites, custom items.

**Nutrition:** Per-ingredient data (USDA FDC), per-recipe/per-serving calculation,
density-based unit resolution, CLI tool (`bin/nutrition`).

**Multi-Tenant Kitchens:** Separate collections, membership access control, public reads,
member-only writes, single-kitchen URL simplification.

**Authentication:** Trusted-header auth (Authelia/Caddy), session cookies, auto-join.

**Deployment:** Single Docker image with SQLite, idempotent seeds, health check `/up`,
CI/CD via GitHub Actions.

## Docker Compose Design

Minimal single-service compose file:
- Image: `ghcr.io/chris-biagini/familyrecipes:latest`
- Port: `127.0.0.1:3030:3030` (localhost only, for reverse proxy)
- Volume: named volume at `/app/storage` (both SQLite databases)
- Required env: `SECRET_KEY_BASE`, `ALLOWED_HOSTS`
- Optional env: `RAILS_LOG_LEVEL`, `USDA_API_KEY`

No PostgreSQL service. No external database.

## Caddy Example

```
recipes.example.com {
    forward_auth authelia:9091 {
        uri /api/authz/forward-auth
        copy_headers Remote-User Remote-Email Remote-Name Remote-Groups
    }
    reverse_proxy app:3030
}
```

## Backup Procedure

**Stopped backup (safest):**
```bash
docker compose stop app
docker cp $(docker compose ps -q app):/app/storage ./backup-$(date +%Y%m%d)
docker compose start app
```

**Live backup (WAL-safe):**
```bash
docker compose exec app sqlite3 /app/storage/production.sqlite3 ".backup '/tmp/primary.sqlite3'"
docker compose exec app sqlite3 /app/storage/production_cable.sqlite3 ".backup '/tmp/cable.sqlite3'"
docker compose cp app:/tmp/primary.sqlite3 ./backup/
docker compose cp app:/tmp/cable.sqlite3 ./backup/
```

## Changes Required

1. Rewrite `README.md` with new structure and content
2. Rewrite `docker-compose.example.yml` (drop PostgreSQL, simplify)
3. No code changes needed — the app itself is deployment-ready
