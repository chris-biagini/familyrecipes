# Settings Page Design

## Goal

Add a settings page for site configuration and API keys, replacing the static
`config/site.yml` with database-backed settings on the Kitchen model. Add a
gear icon to the navbar that stays outside the overflow system.

## Scope

### In scope
- Site config: `site_title`, `homepage_heading`, `homepage_subtitle`
- API keys: `usda_api_key` (encrypted at rest)
- Gear icon in navbar (always visible, no label, members-only)
- Remove `config/site.yml` and its initializer

### Out of scope (deferred)
- `anthropic_api_key` — nothing to wire it to yet
- `unit_preference` — nothing to wire it to yet
- Admin roles — any member can access settings

## Data Model

Add columns to `Kitchen`:

| Column              | Type     | Notes                              |
|---------------------|----------|------------------------------------|
| `site_title`        | `string` | Default: "Family Recipes"          |
| `homepage_heading`  | `string` | Default: "Our Recipes"             |
| `homepage_subtitle` | `string` | Default: "A collection of our family's favorite recipes." |
| `usda_api_key`      | `string` | Encrypted via `encrypts`           |

The `multi_kitchen` flag stays outside the database — it's a deployment
concern, not a user preference.

## Encryption

```ruby
class Kitchen < ApplicationRecord
  encrypts :usda_api_key
end
```

Requires `active_record_encryption` keys in Rails credentials. Generate if
not present.

## Navigation

A gear icon sits to the far right of the navbar, outside both the main nav
links and the `extra_nav` yield area. It does not participate in the
ResizeObserver overflow system — always visible as a small icon with no text
label. Hidden when not logged in (members-only, like the other nav links
after Recipes).

## Page Layout

Single page at `/settings` (kitchen-scoped via the existing optional prefix).
Three sections under clear headings:

1. **Site** — `site_title`, `homepage_heading`, `homepage_subtitle` (text inputs)
2. **API Keys** — `usda_api_key` (password-masked input with reveal toggle)
3. *(Future sections added here as needed)*

One save button at the bottom. Standard form submission via Turbo. Flash
message on success.

## Controller

`SettingsController` with `show` (GET) and `update` (PATCH). Thin controller
— validates and saves directly to `current_kitchen`. No write service needed
(no side effects like broadcasts or cascades).

## Migration from site.yml

- Migration adds columns with defaults matching current `site.yml` values
- Seed backfills existing kitchens from `site.yml` defaults
- Remove `config/site.yml` and `config/initializers/site_config.rb`
- Update all `Rails.configuration.site.*` references to read from
  `current_kitchen` (layout title, homepage view)

## Design Direction

The settings page should feel like a quiet utility — clean, functional,
no decoration. Consistent with the app's existing typography (Futura) and
color system. Card-style sections with subtle borders, generous spacing.
The gear icon matches the existing nav icon style (stroke-only SVG,
`currentColor`, same dimensions).
