# Dev/Production Auth Optimization

Closes #98.

## Context

The trusted-header auth system is in place but the dev experience doesn't match production.
Logged-out users can still access ingredients and groceries pages (which are private-use/admin
pages), and the nav shows a Log Out button that doesn't make sense in a world where Authelia
handles identity.

## Decisions

- **Ingredients and groceries are members-only.** Both read and write paths require membership.
  Homepage and recipe pages remain public reads.
- **No Log Out button in the nav.** In production, Authelia handles auth. In dev, `/logout` and
  `/dev/login/:id` are manual URL tools for testing.
- **Dev mode auto-logs in.** Simulates "always behind Authelia." Uses the seeded user. A cookie
  opt-out lets you test the logged-out experience via `/logout`.
- **Test environment unchanged.** Tests start logged-out and use `log_in` helper explicitly.

## 1. Auth Gate Changes

| Controller | Before | After |
|---|---|---|
| `IngredientsController` | No guard (public) | `require_membership` on all actions |
| `GroceriesController` | `require_membership` on writes only | `require_membership` on all actions |
| `HomepageController` | Public | Public (unchanged) |
| `RecipesController` | Public reads, membership for writes | Unchanged |

Nav links for Ingredients and Groceries are gated on `logged_in?` so logged-out users don't
see links to pages they can't access.

## 2. Dev Auto-Login

A `before_action` in `ApplicationController` runs only in `Rails.env.development?`:

1. If a valid session already exists, do nothing.
2. If `skip_dev_auto_login` cookie is set, do nothing (user explicitly logged out).
3. Otherwise, log in as `User.first` via `start_new_session_for`.

`DevSessionsController#destroy` sets the `skip_dev_auto_login` cookie.
`DevSessionsController#create` deletes it.

## 3. Nav Cleanup

Remove the Log Out button from `_nav.html.erb`. The `/logout` endpoint stays for manual use.
