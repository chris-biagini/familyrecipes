# Structured Self-Hosted Deployment Design

Addresses #187. Moves from ad-hoc homelab builds to a repeatable, upgrade-safe
deployment model targeting single-kitchen homelabbers.

## 1. Schema Consolidation

Collapse the three migrations (`001_create_schema`, `002_add_aliases`,
`003_add_nocase`) into a single `001_create_schema.rb` reflecting the current
`db/schema.rb`. Delete the other two. No production databases exist to migrate —
every deployment builds from scratch via `db:prepare`.

## 2. Single-Kitchen Enforcement

Add `multi_kitchen: false` to `config/site.yml`. Drop the unused `github_url`
key and remove the homepage footer link that references it.

Kitchen model validates on create: if `multi_kitchen` is `false` and a kitchen
already exists, validation fails. Existing multi-kitchen routing and URL logic
stays in place as foundation for the future — the guard just prevents a second
kitchen from being created.

Default config:

```yaml
default: &default
  site_title: Family Recipes
  homepage_heading: Our Recipes
  homepage_subtitle: "A collection of our family's favorite recipes."
  multi_kitchen: false
```

## 3. Config File in Storage Volume

`config/site.yml` ships in the Docker image as the default template. On
container start, the entrypoint copies it to `storage/site.yml` if that file
doesn't already exist. The initializer loads from `storage/site.yml` when
present, falling back to `config/site.yml` for local development.

- **First boot**: default copied to volume, user customizes later
- **Image update**: user's config in the volume is untouched
- **Local dev**: works as-is, no storage copy needed

## 4. Sample Content

Replace the ~35 real family recipes in `db/seeds/recipes/` with ~5-6 made-up
sample recipes demonstrating the full syntax: cross-references, servings vs.
makes, multi-step procedures, scaling in text, implicit single-step, footers.
Plus a sample Quick Bites file. Built from catalog ingredients so nutrition
resolution works out of the box.

`db:seed` installs samples only when `Recipe.count == 0` (fresh install). On
image updates, existing content is untouched.

## 5. Docker Entrypoint

`bin/docker-entrypoint` orchestrates all boot-time setup:

1. `bin/rails db:prepare` — create/migrate DB (idempotent)
2. Copy default `site.yml` to `storage/` if not present
3. `bin/rails catalog:sync` — upsert global ingredient data (idempotent)
4. `bin/rails db:seed` — sample recipes only if no recipes exist
5. Boot Puma

All automatic, all idempotent. User runs `docker compose up -d` and everything
works — first boot or image update. Ingredient catalog improvements propagate on
every image update; per-kitchen overrides are preserved by the overlay model.

## Scope

**In scope**: schema consolidation, site.yml changes, single-kitchen guard,
storage-volume config, sample recipes, entrypoint updates.

**Out of scope**: git tagging/versioning (done separately when ready), GitHub
Actions changes (current workflow is fine), multi-kitchen UI, hosted model.
