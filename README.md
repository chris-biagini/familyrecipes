# familyrecipes

A self-hosted recipe manager for families who cook together. Write recipes in
Markdown, plan your week's meals, generate grocery lists that sync across
devices, and track nutrition — all from a single Docker container backed by
SQLite. No cloud account required.

**[Documentation](https://chris-biagini.github.io/familyrecipes/)** · **[Docker Image](https://github.com/chris-biagini/familyrecipes/pkgs/container/familyrecipes)** · **[Source](https://github.com/chris-biagini/familyrecipes)**

---

## Why familyrecipes?

Most recipe apps are either cloud services that hold your data hostage or
bare-bones tools that stop at storing text. familyrecipes is different:

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
[Cross-reference](https://chris-biagini.github.io/familyrecipes/recipes/cross-references/)
other recipes as ingredients — a bread recipe can pull in your sourdough
starter. [Scale](https://chris-biagini.github.io/familyrecipes/recipes/scaling/)
quantities up or down with a tap. Organize with
[tags and categories](https://chris-biagini.github.io/familyrecipes/recipes/tags-and-categories/).

[Learn more about recipes →](https://chris-biagini.github.io/familyrecipes/recipes/)

### Menu Planning

Pick what you're cooking this week. The
[dinner picker](https://chris-biagini.github.io/familyrecipes/menu/dinner-picker/)
suggests meals based on your history and preferences. Add
[QuickBites](https://chris-biagini.github.io/familyrecipes/menu/quickbites/)
for non-recipe items like snacks and staples. Your selections feed directly
into the grocery list.

[Learn more about the menu →](https://chris-biagini.github.io/familyrecipes/menu/)

### Grocery Lists

Shopping lists are
[generated automatically](https://chris-biagini.github.io/familyrecipes/groceries/how-it-works/)
from your menu selections, grouped by aisle, and
[synced in real time](https://chris-biagini.github.io/familyrecipes/groceries/)
across every open tab and device. The system
[learns your pantry](https://chris-biagini.github.io/familyrecipes/groceries/learning/)
over time — items you always have on hand stop showing up. Screen stays awake
while you shop.

[Learn more about groceries →](https://chris-biagini.github.io/familyrecipes/groceries/)

### Nutrition

Per-ingredient nutrition data sourced from
[USDA FoodData Central](https://fdc.nal.usda.gov/). Automatic per-recipe and
per-serving calculation with density-based unit resolution. Manage your
ingredient catalog through the
[web-based editor](https://chris-biagini.github.io/familyrecipes/ingredients/nutrition-data/).

[Learn more about nutrition →](https://chris-biagini.github.io/familyrecipes/recipes/nutrition/)

### Import & Export

Paste a recipe from any source and let the
[AI import](https://chris-biagini.github.io/familyrecipes/import-export/ai-import/)
parse it into structured format (requires an Anthropic API key). Bulk-import
Markdown files or ZIP archives. Export everything as a portable ZIP.

[Learn more about import & export →](https://chris-biagini.github.io/familyrecipes/import-export/)

### Multi-Tenant Kitchens

Run separate recipe collections for different households on the same instance.
Recipes are publicly readable; editing and grocery lists require membership.
When only one kitchen exists, URLs stay clean — no `/kitchens/:slug` prefix.

---

## Quick Start

### 1. Download and start

```bash
mkdir familyrecipes && cd familyrecipes
curl -O https://raw.githubusercontent.com/chris-biagini/familyrecipes/main/docker-compose.example.yml
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
| `TRUSTED_PROXY_IPS` | `127.0.0.0/8,::1/128` | CIDR allowlist of reverse proxies allowed to set trusted-auth headers. Empty string disables trusted-header auth entirely. See "Trust model" below. |
| `TRUSTED_HEADER_USER` | `Remote-User` | HTTP header carrying the username/identifier from your reverse proxy. |
| `TRUSTED_HEADER_EMAIL` | `Remote-Email` | HTTP header carrying the user's email. |
| `TRUSTED_HEADER_NAME` | `Remote-Name` | HTTP header carrying the user's display name. |

### 4. Add authentication (production)

familyrecipes supports two complementary auth paths:

1. **Passwordless join codes** — 4-word cooking-themed codes you share
   with trusted people. No setup, works anywhere. See the in-app
   settings dialog to view or regenerate the join code for a kitchen.
2. **Trusted-header auth** — for homelab installs running a reverse
   proxy with SSO ([Authelia](https://www.authelia.com/),
   [Authentik](https://goauthentik.io/),
   [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/), Caddy's
   `forward_auth`, etc.). The proxy authenticates the user and sets
   HTTP headers that familyrecipes reads to identify them.

Both paths coexist — trusted headers are checked first, passwordless
join codes are the fallback.

#### Trust model

> **Your reverse proxy MUST strip any inbound `Remote-User`,
> `Remote-Email`, and `Remote-Name` headers from external requests
> before forwarding to familyrecipes.** If you cannot guarantee this,
> see "Disabling trusted-header auth" below.

A misconfigured proxy that passes through client-supplied `Remote-User`
headers lets an attacker impersonate any user on your install. This is
the dominant failure mode for trusted-header auth in self-hosted apps.

familyrecipes defends against this in two layers:

1. **Peer IP allowlist (`TRUSTED_PROXY_IPS`).** Trusted headers are
   only honored when the TCP peer — the actual host that opened the
   connection to familyrecipes — is in a configured CIDR allowlist.
   Default is `127.0.0.0/8,::1/128`, which covers same-host
   docker-compose installs with zero configuration. If your reverse
   proxy is on a separate host or in a different docker network, set
   `TRUSTED_PROXY_IPS` to the proxy's address range (comma-separated
   CIDRs, e.g. `172.18.0.0/16,10.0.0.5/32`). A request from any other
   peer IP is treated as anonymous — the headers are ignored entirely.
2. **Your proxy's header strip rules.** Even with the peer IP check,
   your reverse proxy should still strip inbound `Remote-*` headers
   from external requests as a defense-in-depth layer. The example
   Caddy config below shows how.

#### The underscore/dash footgun

HTTP header names are case-insensitive, but Rack converts them to env
variables by replacing `-` with `_`. This means `Remote-User` and
`Remote_User` (underscore) end up in the same slot. **nginx strips
headers containing underscores by default; Caddy, Traefik, and HAProxy
do not.** Operators on non-nginx proxies must explicitly strip both
forms or they leave a bypass open:

- Caddy: `header_up -Remote-User` (the `-` prefix deletes)
- Traefik: `customRequestHeaders: Remote-User: ""`
- HAProxy: `http-request del-header Remote-User`

Do the same for `Remote-Email` and `Remote-Name`.

#### Example Caddy configuration

```
recipes.example.com {
    # Strip ANY inbound client-supplied auth headers first.
    request_header -Remote-User
    request_header -Remote-Email
    request_header -Remote-Name
    request_header -Remote-Groups

    forward_auth authelia:9091 {
        uri /api/authz/forward-auth
        copy_headers Remote-User Remote-Email Remote-Name Remote-Groups
    }
    reverse_proxy familyrecipes-app:3030
}
```

The `request_header -Remote-User` lines are critical — they run before
`forward_auth`, so Authelia is the only code that can re-set those
headers. Without them, a client sending `Remote-User: admin` would
reach familyrecipes with that header intact.

The app expects `X-Forwarded-Proto: https` from the proxy (Caddy sends
this by default). Without a TLS-terminating proxy, `force_ssl` causes
a redirect loop. The `/up` health endpoint is excluded from SSL
redirect and host checks.

#### Custom header names

If your proxy emits different header names (Grafana-style
`X-Webauth-User`, oauth2-proxy's `X-Auth-Username`, etc.), set these
env vars:

```
TRUSTED_HEADER_USER=X-Webauth-User
TRUSTED_HEADER_EMAIL=X-Webauth-Email
TRUSTED_HEADER_NAME=X-Webauth-Name
```

Defaults are `Remote-User` / `Remote-Email` / `Remote-Name` (the
Authelia convention).

#### Disabling trusted-header auth

If you cannot guarantee that your reverse proxy strips inbound
`Remote-*` headers — or if you just don't want trusted-header auth at
all — disable it explicitly by setting:

```
TRUSTED_PROXY_IPS=
```

An **empty** value (not unset) produces an empty allowlist: every
request fails the peer IP check, and trusted headers are ignored
unconditionally. Users must sign in via join code or the re-auth link
in the welcome email.

**Unset** (env var missing entirely) falls back to the loopback
default — it does *not* disable trusted-header auth. The distinction
matters: "unset" means "I want the default", "empty" means "I want it
off".

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
git clone https://github.com/chris-biagini/familyrecipes.git
cd familyrecipes
bundle install && npm install
rails db:setup
bin/dev
```

Starts the app at `http://localhost:3030` with auto-login in development mode.

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

[GNU Affero General Public License v3.0](LICENSE.md) — Copyright (c) 2025
Christopher Biagini.
