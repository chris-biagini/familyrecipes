# API Keys to Environment Variables

**Date:** 2026-04-12
**Issues:** #366, #367
**Status:** Design

## Context

USDA and Anthropic API keys are currently stored as encrypted columns on the
`Kitchen` model, set per-tenant through the Settings UI. This made sense for a
homelab-only app where each household manages its own keys, but doesn't fit
the upcoming hosted deployment where the operator supplies shared keys via
Kamal's 1Password-backed secrets management.

## Decision

Move both keys to environment variables. Remove per-kitchen storage entirely.

**Rationale:** There's no real use case for per-kitchen API keys. A homelab
with multiple kitchens is one household with one USDA key. For hosted mode,
the operator controls costs and visibility. Simplify now; add per-kitchen
override later only if a real need emerges.

Rate limiting for AI imports (the "10 free imports/month" idea from #367)
is out of scope — it deserves its own design and issue.

## Data Flow

```
Hosted:  1Password vault → .kamal/secrets → ENV vars in container
Homelab: docker-compose env section       → ENV vars in container
                                              ↓
                              app reads ENV['USDA_API_KEY']
                              app reads ENV['ANTHROPIC_API_KEY']
```

Services read `ENV` directly. When the env var is blank or absent, existing
graceful degradation kicks in — USDA search shows "no key configured", AI
import returns an error. No behavioral change from the user's perspective.

## Removals

### Database

Migration to remove two columns from `kitchens`:

- `usda_api_key` (string, encrypted)
- `anthropic_api_key` (string, encrypted)

### Kitchen Model

- Drop `encrypts :usda_api_key`
- Drop `encrypts :anthropic_api_key`
- Update the architectural header comment to remove API key references

### Settings UI

- Remove the "API Keys" section from `app/views/settings/_editor_frame.html.erb`
  (password inputs, show/hide toggles, labels — roughly lines 49-76)
- Remove `usda_api_key` / `anthropic_api_key` from `filtered_settings_params`
  in `SettingsController`
- Remove the `usda_api_key_set` / `anthropic_api_key_set` flags passed to
  the view
- Remove the `usdaApiKey` / `anthropicApiKey` Stimulus targets and their
  modification tracking from `settings_editor_controller.js`

## Changes

### UsdaSearchController

`current_kitchen.usda_api_key` → `ENV['USDA_API_KEY']`. The
`require_api_key` before_action stays; it checks the env var instead of
the model attribute.

### AiImportService

`kitchen.anthropic_api_key` → `ENV['ANTHROPIC_API_KEY']`. The constructor
no longer reads the kitchen's API key (it still needs the kitchen for
categories/tags in the system prompt). The blank-key guard stays. Update
the `AuthenticationError` rescue message — it currently says "Check your
key in Settings" which no longer applies.

### docker-compose.example.yml

Uncomment `USDA_API_KEY`, add `ANTHROPIC_API_KEY`. Both optional, with
comments explaining what features they enable.

### .env.example

Add both keys with comments.

## Unchanged

- `Kitchen::AI_MODEL` stays on the model — product decision, not a secret.
- AR encryption config and the three `ACTIVE_RECORD_ENCRYPTION_*` keys are
  untouched (still needed for `join_code`).
- No rate limiting — separate issue.

## Test Impact

- Tests that set `@kitchen.update!(usda_api_key: ...)` switch to
  `ENV['USDA_API_KEY'] = 'test-key'` with teardown cleanup.
- Tests that assert `no_api_key` behavior remain; they just need the env var
  absent rather than the column blank.
- No new test files — existing coverage adapts in place.

## Kamal Alignment

This work prepares the app for Kamal's secrets model (#390). When
`config/deploy.yml` is written, both keys will appear in `env.secret` and
be fetched from 1Password via `.kamal/secrets`:

```yaml
# config/deploy.yml (future, illustrative)
env:
  secret:
    - USDA_API_KEY
    - ANTHROPIC_API_KEY
```

```bash
# .kamal/secrets (future, illustrative)
SECRETS=$(kamal secrets fetch --adapter 1password \
  --from "Mirepoix Production" \
  USDA_API_KEY ANTHROPIC_API_KEY)

USDA_API_KEY=$(kamal secrets extract USDA_API_KEY $SECRETS)
ANTHROPIC_API_KEY=$(kamal secrets extract ANTHROPIC_API_KEY $SECRETS)
```

The exact Kamal config is #390's concern. This work just ensures the app
reads from `ENV` so that Kamal can inject the values.
