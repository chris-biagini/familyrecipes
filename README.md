# familyrecipes

A self-hosted recipe manager built with Ruby on Rails. Author recipes in Markdown, build grocery lists, track nutrition, and share a kitchen with your household — all from a single Docker container backed by SQLite.

Inspired by the beautifully-designed [Paprika](https://www.paprikaapp.com) by Hindsight Labs.

## Features

**Recipes** — Author recipes in Markdown with structured steps, ingredients, and metadata. Edit recipes in the browser. Cross-reference other recipes as ingredients (e.g., a bread recipe that uses your sourdough starter). Scale ingredient quantities up or down with a click.

**Grocery Lists** — Build shopping lists from selected recipes. Items are grouped by grocery aisle with customizable ordering. Check off items as you shop. Add custom items that aren't part of any recipe. Quick Bites provide lightweight grocery bundles for common shopping runs. Lists sync in real time across all open tabs and devices.

**Nutrition** — Per-ingredient nutrition data sourced from USDA FoodData Central. Automatic per-recipe and per-serving nutrition calculation with density-based unit resolution (weight, volume, and named portions like "1 stick"). Includes a CLI tool (`bin/nutrition`) for managing the ingredient catalog.

**Kitchens** — Multi-tenant support for separate recipe collections. Membership-based access control: recipes are publicly readable, but editing and grocery lists require membership. When only one kitchen exists, URLs are simplified (no `/kitchens/:slug` prefix).

**Authentication** — Designed for deployment behind a reverse proxy with trusted-header authentication (Authelia, Authentik, etc.). The proxy sets `Remote-User`, `Remote-Email`, and `Remote-Name` headers; the app reads them to identify users and establish sessions. New users are automatically added to the kitchen when only one exists.

## Tech Stack

- [Ruby on Rails 8](https://rubyonrails.org/) with [SQLite](https://sqlite.org/)
- [Solid Cable](https://github.com/rails/solid_cable) for ActionCable pub/sub
- [Puma](https://puma.io/) web server
- [Propshaft](https://github.com/rails/propshaft) asset pipeline (no Node, no bundler)
- [Redcarpet](https://github.com/vmg/redcarpet) for Markdown rendering
- [Claude Code](https://claude.ai/code) by [Anthropic](https://www.anthropic.com/)

## Quick Start (Docker)

The recommended deployment is Docker behind [Caddy](https://caddyserver.com/) and [Authelia](https://www.authelia.com/).

### 1. Create a docker-compose.yml

```bash
mkdir familyrecipes && cd familyrecipes
curl -O https://raw.githubusercontent.com/chris-biagini/familyrecipes/main/docker-compose.example.yml
curl -O https://raw.githubusercontent.com/chris-biagini/familyrecipes/main/.env.example
cp docker-compose.example.yml docker-compose.yml
cp .env.example .env
```

### 2. Configure your .env

Generate a secret key and add it to `.env`:

```bash
docker run --rm ruby:3.2-slim ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
```

Copy the output into `.env` as `SECRET_KEY_BASE`. Set `ALLOWED_HOSTS` to your domain (e.g., `recipes.example.com`) for DNS rebinding protection. Keep `.env` out of version control — it holds your secrets.

### 3. Start the container

```bash
docker compose up -d
```

On first start, the entrypoint creates the database, runs migrations, and seeds recipe data. The app is available at `http://localhost:3030`. Subsequent starts skip already-applied migrations and already-imported recipes.

### 4. Configure Caddy and Authelia

Add a Caddyfile entry for your domain:

```
recipes.example.com {
    forward_auth authelia:9091 {
        uri /api/authz/forward-auth
        copy_headers Remote-User Remote-Email Remote-Name Remote-Groups
    }
    reverse_proxy familyrecipes-app:3030
}
```

Caddy terminates TLS and forwards authenticated requests to the app. The app expects `X-Forwarded-Proto: https` from the reverse proxy (Caddy sends this by default). Without a TLS-terminating proxy, the app will enter a redirect loop due to `force_ssl`.

The health check endpoint at `/up` is excluded from SSL redirect and host authorization, making it safe for Docker health probes and uptime monitors.

## Configuration

All configuration is done through environment variables in your `.env` file. Docker Compose reads `.env` automatically when it's in the same directory as `docker-compose.yml`. See `.env.example` for a template.

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY_BASE` | Yes | — | Rails session encryption key. Generate with the command above. |
| `ALLOWED_HOSTS` | Recommended | allow all | Comma-separated domain(s) for DNS rebinding protection. |
| `RAILS_LOG_LEVEL` | No | `info` | Log verbosity: `debug`, `info`, `warn`, `error`. |
| `USDA_API_KEY` | No | — | Enables USDA FoodData Central lookups in `bin/nutrition`. Free at [fdc.nal.usda.gov](https://fdc.nal.usda.gov/api-key-signup). |

## Backups

Both SQLite databases (recipes and ActionCable) live in the Docker volume mounted at `/app/storage`. Back up this volume regularly.

**Offline backup (safest):**

```bash
docker compose stop app
docker cp $(docker compose ps -q app):/app/storage ./backup-$(date +%Y%m%d)
docker compose start app
```

**Online backup (zero downtime):**

SQLite's WAL mode makes it safe to create a consistent backup while the app is running:

```bash
mkdir -p backup
docker compose exec app sqlite3 /app/storage/production.sqlite3 ".backup '/tmp/primary.sqlite3'"
docker compose exec app sqlite3 /app/storage/production_cable.sqlite3 ".backup '/tmp/cable.sqlite3'"
docker compose cp app:/tmp/primary.sqlite3 ./backup/
docker compose cp app:/tmp/cable.sqlite3 ./backup/
```

The cable database holds only ephemeral pub/sub messages and can be safely discarded if needed. The primary database is the one that matters.

## Updating

```bash
docker compose pull
docker compose up -d
```

The entrypoint runs `db:prepare` and `db:seed` on every start. Both are idempotent:

- **Migrations** are applied only if not already present.
- **Seed recipes** are imported only if they don't already exist. Recipes you've edited in the browser are never overwritten — the seeder skips any recipe with a web edit timestamp.
- **New recipes** added in a code update are imported on the next container start.

## Development

```bash
git clone https://github.com/chris-biagini/familyrecipes.git
cd familyrecipes
bundle install
rails db:create db:migrate db:seed
bin/dev
```

This starts the app at `http://localhost:3030`. In development, you're automatically logged in as the first user.

**Run tests:**

```bash
rake          # lint + tests
rake test     # tests only
rake lint     # RuboCop only
```

## Credits

Built with [Ruby on Rails](https://rubyonrails.org/), [Claude Code](https://claude.ai/code), and [ChatGPT](https://chatgpt.com/). Favicon generated with [RealFaviconGenerator](https://realfavicongenerator.net/).
