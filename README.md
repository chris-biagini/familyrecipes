# mirepoix

A self-hosted recipe manager for families who cook together. Write recipes in
Markdown, plan your week's meals, generate grocery lists that sync across
devices, and track nutrition — all from a single Docker container backed by
SQLite. No cloud account required.

**[Documentation](https://chris-biagini.github.io/mirepoix/)** · **[Docker Image](https://github.com/chris-biagini/mirepoix/pkgs/container/mirepoix)** · **[Source](https://github.com/chris-biagini/mirepoix)**

---

## Why mirepoix?

Most recipe apps are either cloud services that hold your data hostage or
bare-bones tools that stop at storing text. mirepoix is different:

- **Your data, your server.** Runs on any machine with Docker — a Raspberry Pi,
  a NAS, a VPS. SQLite means zero external dependencies.
- **Real-time grocery lists.** One person adds a recipe to the menu, everyone's
  shopping list updates instantly. Check items off your phone while your partner
  adds a last-minute dinner at home.
- **Markdown-native.** Recipes are plain text with a lightweight syntax. Paste
  from anywhere, edit in the browser, export anytime. No lock-in.
- **Installable PWA.** Add it to your home screen and it feels like a native
  app — no app store required.

## Features

### Recipes

Write recipes in Markdown with structured steps, ingredients, and metadata.
Edit in a graphical editor or switch to plaintext with syntax highlighting.
[Cross-reference](https://chris-biagini.github.io/mirepoix/recipes/cross-references/)
other recipes as ingredients — a bread recipe can pull in your sourdough
starter. [Scale](https://chris-biagini.github.io/mirepoix/recipes/scaling/)
quantities up or down with a tap. Organize with
[tags and categories](https://chris-biagini.github.io/mirepoix/recipes/tags-and-categories/).

[Learn more about recipes →](https://chris-biagini.github.io/mirepoix/recipes/)

### Menu Planning

Pick what you're cooking this week. The
[dinner picker](https://chris-biagini.github.io/mirepoix/menu/dinner-picker/)
suggests meals based on your history and preferences. Add
[QuickBites](https://chris-biagini.github.io/mirepoix/menu/quickbites/)
for non-recipe items like snacks and staples. Your selections feed directly
into the grocery list.

[Learn more about the menu →](https://chris-biagini.github.io/mirepoix/menu/)

### Grocery Lists

Shopping lists are
[generated automatically](https://chris-biagini.github.io/mirepoix/groceries/how-it-works/)
from your menu selections, grouped by aisle, and
[synced in real time](https://chris-biagini.github.io/mirepoix/groceries/)
across every open tab and device. The system
[learns your pantry](https://chris-biagini.github.io/mirepoix/groceries/learning/)
over time — items you always have on hand stop showing up. Screen stays awake
while you shop.

[Learn more about groceries →](https://chris-biagini.github.io/mirepoix/groceries/)

### Nutrition

Per-ingredient nutrition data sourced from
[USDA FoodData Central](https://fdc.nal.usda.gov/). Automatic per-recipe and
per-serving calculation with density-based unit resolution. Manage your
ingredient catalog through the
[web-based editor](https://chris-biagini.github.io/mirepoix/ingredients/nutrition-data/).

[Learn more about nutrition →](https://chris-biagini.github.io/mirepoix/recipes/nutrition/)

### Import & Export

Paste a recipe from any source and let the
[AI import](https://chris-biagini.github.io/mirepoix/import-export/ai-import/)
parse it into structured format (requires an Anthropic API key). Bulk-import
Markdown files or ZIP archives. Export everything as a portable ZIP.

[Learn more about import & export →](https://chris-biagini.github.io/mirepoix/import-export/)

### Multi-Tenant Kitchens

Run separate recipe collections for different households on the same instance.
Recipes are publicly readable; editing and grocery lists require membership.
When only one kitchen exists, URLs stay clean — no `/kitchens/:slug` prefix.

---

## Quick Start

### 1. Download and start

```bash
mkdir mirepoix && cd mirepoix
curl -O https://raw.githubusercontent.com/chris-biagini/mirepoix/main/docker-compose.example.yml
cp docker-compose.example.yml docker-compose.yml
docker compose up -d
```

On first start, the entrypoint generates encryption keys (persisted in the
storage volume), creates the database, syncs the ingredient catalog, and
seeds sample recipes. Subsequent starts apply new migrations and sync the
catalog automatically.

### 2. Verify

```bash
curl -s http://localhost:3030/up
```

Visit **http://localhost:3030** to see the sample recipes.

### 3. Configure (optional)

Create a `.env` file (see `.env.example`) to set `ALLOWED_HOSTS`, provide your
own `SECRET_KEY_BASE`, or add a USDA API key for nutrition lookups. A `site.yml`
is created in the storage volume on first boot — edit it to customize your site
title and homepage text.

| Variable | Default | Description |
|---|---|---|
| `SECRET_KEY_BASE` | auto-generated | Rails session encryption key |
| `ALLOWED_HOSTS` | allow all | Comma-separated domain(s) for DNS rebinding protection |
| `RAILS_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |
| `USDA_API_KEY` | — | Free at [fdc.nal.usda.gov](https://fdc.nal.usda.gov/api-key-signup) |
| `ANTHROPIC_API_KEY` | — | Optional; enables AI-powered recipe import in the recipe editor |

### 4. Sign in (production)

mirepoix uses passwordless magic-link auth. To sign in, enter your
email address on the sign-in page; the app sends a one-time link that
logs you in when clicked. Joining a kitchen also uses a 4-word
cooking-themed join code that the owner shares with you — enter the
code plus your email, click the link, and you're in.

**Email delivery.** Set `SMTP_*` and `MAILER_FROM_ADDRESS` in your
`.env` to send real email (see `.env.example`). If `SMTP_ADDRESS` is
unset, the app falls back to **logger delivery**: the full magic link
is printed to the container log (`docker compose logs app`) so you can
still sign in on a homelab install with no mail relay configured. This
is intended for single-admin homelab use — don't run logger delivery
for multi-user installs.

The app expects `X-Forwarded-Proto: https` from your reverse proxy.
Without a TLS-terminating proxy, `force_ssl` causes a redirect loop.
The `/up` health endpoint is excluded from SSL redirect and host
checks.

---

## Updating

```bash
docker compose pull
docker compose up -d
```

Migrations, catalog sync, and seed are idempotent — safe to run on every start.
Sample recipes are only seeded when no recipes exist.

## Backups

Both SQLite databases and your `site.yml` live in the Docker volume at
`/app/storage`. Back up this volume regularly.

**Online backup (zero downtime):**

```bash
mkdir -p backup
docker compose exec app sqlite3 /app/storage/production.sqlite3 ".backup '/tmp/primary.sqlite3'"
docker compose cp app:/tmp/primary.sqlite3 ./backup/
```

**Offline backup:**

```bash
docker compose stop app
docker cp $(docker compose ps -q app):/app/storage ./backup-$(date +%Y%m%d)
docker compose start app
```

The cable database (`production_cable.sqlite3`) holds only ephemeral pub/sub
messages and can be safely discarded.

> **Bind mounts:** The container runs as UID 1000. If using a bind mount
> instead of a named volume, ensure the host directory is writable:
> `chown -R 1000:1000 ./storage`.

## Development

```bash
git clone https://github.com/chris-biagini/mirepoix.git
cd mirepoix
bundle install && npm install
rails db:setup
bin/dev
```

Starts the app at `http://localhost:3030`. Visit `/dev/login/1` to sign in as the first seeded user.

```bash
rake          # lint + tests
rake test     # Minitest only
rake lint     # RuboCop only
rake security # Brakeman static analysis
```

---

## Built With

- [Ruby on Rails](https://rubyonrails.org/) — web framework
- [SQLite](https://sqlite.org/) — database
- [Hotwire](https://hotwired.dev/) (Turbo + Stimulus) — real-time UI without heavy JavaScript
- [Solid Cable](https://github.com/rails/solid_cable) — ActionCable adapter backed by SQLite
- [CodeMirror](https://codemirror.net/) — in-browser code editor (MIT License)
- [Redcarpet](https://github.com/vmg/redcarpet) — Markdown rendering
- [Propshaft](https://github.com/rails/propshaft) — asset pipeline
- [Puma](https://puma.io/) — web server
- [acts_as_tenant](https://github.com/ErwinM/acts_as_tenant) — multi-tenancy scoping
- [RubyZip](https://github.com/rubyzip/rubyzip) — ZIP import/export (BSD 2-Clause License)
- [esbuild](https://esbuild.github.io/) — JavaScript bundling

### Tools

- [Claude Code](https://claude.ai/code) by [Anthropic](https://www.anthropic.com/)
- [ChatGPT](https://chatgpt.com/) by [OpenAI](https://openai.com/)
- [RealFaviconGenerator](https://realfavicongenerator.net/)

Inspired by [Paprika](https://www.paprikaapp.com/) by Hindsight Labs.

## License

[O'Saasy License](LICENSE.md) — Copyright (c) 2025 Christopher Biagini.

Mirepoix is free to self-host. The license reserves the right to offer
Mirepoix as a hosted SaaS product to the copyright holder. See
[osaasy.dev](https://osaasy.dev) for background on the license.
