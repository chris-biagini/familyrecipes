# Login Page Design

**Date:** 2026-02-22
**Status:** Approved

## Problem

OmniAuth 2.x with `omniauth-rails_csrf_protection` requires POST for the request phase (`/auth/developer`). A direct GET fails with "No route matches." The app has no login page or login/logout nav links.

## Design

### Route

`GET /login` handled by `SessionsController#new`. Permanent route — not dev-only.

### Controller

`SessionsController` with a single `new` action. OmniAuth continues to own the callback flow via `OmniauthCallbacksController`.

### View

A centered card matching the cookbook aesthetic. In dev/test, renders the OmniAuth developer form: name and email fields that POST to `/auth/developer`. Production will add OAuth provider buttons to the same page.

### Nav

`_nav.html.erb` gets a right-aligned "Log in" link (when anonymous) or "Log out" button (when authenticated). Log out uses `button_to` with `method: :delete` to `logout_path`.

### Auth redirect

`Authentication#request_authentication` redirects to `login_path` instead of hardcoded `/auth/developer`. Works in all environments.

## Files Changed

- `config/routes.rb` — add `get 'login'` route, fix callback to `post`
- `app/controllers/sessions_controller.rb` — new controller, renders form
- `app/views/sessions/new.html.erb` — login form view
- `app/views/shared/_nav.html.erb` — login/logout link
- `app/controllers/concerns/authentication.rb` — redirect to `login_path`
- `app/assets/stylesheets/style.css` — login page styling
- Tests for new controller and updated auth flow
