# Docker Packaging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Containerize the familyrecipes Rails app with auto-build via GitHub Actions and push to GHCR, deployable on a homelab server via docker-compose.

**Architecture:** Multi-stage Dockerfile (builder + runtime) on `ruby:3.2-slim`. GitHub Actions builds on push to `main` and pushes to `ghcr.io/chris-biagini/familyrecipes`. A `docker-compose.example.yml` ships in the repo as a deployment reference.

**Tech Stack:** Docker, GitHub Actions, GHCR, PostgreSQL 16, Puma

**Design doc:** `docs/plans/2026-02-22-docker-packaging-design.md`

---

### Task 1: Create .dockerignore

**Files:**
- Create: `.dockerignore`

**Step 1: Create the file**

```
.git
.env
.env.example
.claude/
.playwright-mcp/
.nova/
.bundle/
.DS_Store
tmp/
log/
test/
docs/
node_modules/
*.png
vendor/bundle/
```

Keep `db/seeds/` in the image — the entrypoint runs `db:seed`.

**Step 2: Commit**

```bash
git add .dockerignore
git commit -m "chore: add .dockerignore"
```

---

### Task 2: Create entrypoint script

**Files:**
- Create: `bin/docker-entrypoint`

**Step 1: Write the entrypoint**

```bash
#!/bin/bash
set -e

echo "Preparing database..."
bin/rails db:prepare

echo "Seeding data..."
bin/rails db:seed

echo "Starting server..."
exec "$@"
```

`db:prepare` creates or migrates. `db:seed` is idempotent (uses `find_or_create_by!` throughout `db/seeds.rb`). `exec "$@"` replaces the shell with Puma so signals propagate correctly.

**Step 2: Make it executable**

```bash
chmod +x bin/docker-entrypoint
```

**Step 3: Commit**

```bash
git add bin/docker-entrypoint
git commit -m "chore: add Docker entrypoint script"
```

---

### Task 3: Create Dockerfile

**Files:**
- Create: `Dockerfile`

**Step 1: Write the multi-stage Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1

# ---- Builder stage ----
FROM ruby:3.2-slim AS builder

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without "development test" && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/cache /usr/local/bundle/cache

COPY . .

RUN SECRET_KEY_BASE=placeholder bin/rails assets:precompile

# ---- Runtime stage ----
FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libpq5 && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system rails && \
    useradd --system --gid rails --create-home rails

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app /app

RUN chown -R rails:rails /app/tmp /app/log /app/db

USER rails

EXPOSE 3030

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3030"]
```

Notes:
- `Gemfile`/`Gemfile.lock` copied first for layer caching — app changes don't re-install gems.
- `SECRET_KEY_BASE=placeholder` is needed at build time for `assets:precompile` to not fail (Propshaft needs Rails to boot, Rails needs the secret). This throwaway value is never used at runtime.
- Runtime stage has no compiler, no build tools — only `libpq5` for PostgreSQL.
- Non-root `rails` user owns only `tmp/`, `log/`, `db/` (for sqlite file locks during migration, if any).

**Step 2: Commit**

```bash
git add Dockerfile
git commit -m "chore: add multi-stage Dockerfile"
```

---

### Task 4: Create docker-compose.example.yml

**Files:**
- Create: `docker-compose.example.yml`

**Step 1: Write the example compose file**

```yaml
# docker-compose.example.yml
#
# Reference configuration for deploying familyrecipes.
# Copy to docker-compose.yml and fill in your values.
#
# Quick start:
#   1. cp docker-compose.example.yml docker-compose.yml
#   2. Generate a secret: docker run --rm ruby:3.2-slim ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
#   3. Fill in SECRET_KEY_BASE and database credentials below
#   4. docker compose up -d

services:
  db:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: familyrecipes
      POSTGRES_PASSWORD: CHANGE_ME
      POSTGRES_DB: familyrecipes_production
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U familyrecipes"]
      interval: 5s
      timeout: 5s
      retries: 5

  app:
    image: ghcr.io/chris-biagini/familyrecipes:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "127.0.0.1:3030:3030"
    environment:
      RAILS_ENV: production
      DATABASE_HOST: db
      DATABASE_USERNAME: familyrecipes
      DATABASE_PASSWORD: CHANGE_ME
      SECRET_KEY_BASE: CHANGE_ME
      RAILS_LOG_LEVEL: info

volumes:
  pgdata:
```

Notes:
- `127.0.0.1:3030` — only reachable from localhost, the reverse proxy connects here.
- `CHANGE_ME` placeholders are obvious and greppable.
- `depends_on` with health check ensures Postgres is accepting connections before the app starts.
- No `WEB_CONCURRENCY` set — defaults to 1 worker, which is fine for a homelab.

**Step 2: Commit**

```bash
git add docker-compose.example.yml
git commit -m "chore: add docker-compose.example.yml"
```

---

### Task 5: Create GitHub Actions workflow

**Files:**
- Create: `.github/workflows/docker.yml`

**Step 1: Create the workflow directory**

```bash
mkdir -p .github/workflows
```

**Step 2: Write the workflow**

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=latest
            type=sha,prefix=

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Notes:
- `permissions: packages: write` is required for GHCR push — uses the built-in `GITHUB_TOKEN`, no secrets to configure.
- `docker/metadata-action` generates both `latest` and short-SHA tags automatically.
- `cache-from/cache-to: type=gha` uses GitHub Actions cache for Docker layers — fast rebuilds.
- `docker/build-push-action@v6` is the current latest major version.

**Step 3: Commit**

```bash
git add .github/workflows/docker.yml
git commit -m "ci: add GitHub Actions workflow for Docker build"
```

---

### Task 6: Adjust production config for reverse proxy

**Files:**
- Modify: `config/environments/production.rb:24-31`

**Step 1: Uncomment the health check SSL exclusion**

The current config has `force_ssl = true` and `assume_ssl = true`, which is correct for a reverse-proxy setup. However, the health check path (`/up`) needs to work over plain HTTP for Docker health checks (the container itself doesn't have TLS).

Uncomment line 31 in `config/environments/production.rb`:

```ruby
  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
```

**Step 2: Run tests to make sure nothing broke**

```bash
rake test
```

**Step 3: Commit**

```bash
git add config/environments/production.rb
git commit -m "fix: exclude health check from SSL redirect for container probes"
```

---

### Task 7: Update .env.example with Docker notes

**Files:**
- Modify: `.env.example`

**Step 1: Add Docker deployment section**

Append to `.env.example`:

```
# Docker deployment
# Generate with: ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
# SECRET_KEY_BASE=
# DATABASE_HOST=db
# DATABASE_USERNAME=familyrecipes
# DATABASE_PASSWORD=
```

This gives developers a heads-up that these vars exist for Docker, without changing the dev workflow.

**Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: add Docker env vars to .env.example"
```

---

### Task 8: Test Docker build locally

**Step 1: Build the image**

```bash
docker build -t familyrecipes:test .
```

Expected: successful build, image ~150-200MB.

**Step 2: Verify image contents**

```bash
docker run --rm familyrecipes:test bin/rails --version
```

Expected: `Rails 8.1.2`

**Step 3: Verify non-root user**

```bash
docker run --rm familyrecipes:test whoami
```

Expected: `rails`

**Step 4: Test with docker-compose**

```bash
cp docker-compose.example.yml docker-compose.test.yml
```

Edit `docker-compose.test.yml`: replace `CHANGE_ME` values, set `image: familyrecipes:test` for the app service.

```bash
docker compose -f docker-compose.test.yml up -d
```

Wait for startup, then:

```bash
curl -s http://127.0.0.1:3030/up
```

Expected: HTTP 200 with "OK" or similar health check response.

**Step 5: Verify recipes loaded**

```bash
curl -s http://127.0.0.1:3030/ | head -20
```

Expected: HTML landing page with kitchen listing.

**Step 6: Clean up**

```bash
docker compose -f docker-compose.test.yml down -v
rm docker-compose.test.yml
```

---

### Task 9: Update CLAUDE.md deployment section

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the Deployment section**

Replace the existing Deployment section with:

```markdown
## Deployment

Docker image built by GitHub Actions on push to `main`, pushed to `ghcr.io/chris-biagini/familyrecipes`. Tagged with `latest` and the git SHA.

**On the server:**
```bash
docker compose pull && docker compose up -d
```

The container entrypoint runs `db:prepare` and `db:seed` automatically. Health check at `/up` is ready for container orchestration.

**Local Docker testing:**
```bash
docker build -t familyrecipes:test .
```

See `docker-compose.example.yml` for a reference deployment configuration.
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update deployment section for Docker"
```

---

### Task 10: Push and verify GitHub Actions

**Step 1: Push to main**

```bash
git push origin main
```

**Step 2: Watch the workflow run**

```bash
gh run watch
```

Expected: the "Build and Push Docker Image" workflow completes successfully.

**Step 3: Verify the image is on GHCR**

```bash
gh api user/packages/container/familyrecipes/versions --jq '.[0].metadata.container.tags'
```

Expected: `["latest", "<sha>"]`
