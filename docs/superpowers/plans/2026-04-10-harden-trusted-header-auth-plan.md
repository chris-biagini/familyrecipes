# Harden Trusted-Header Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add defense-in-depth to `ApplicationController#authenticate_from_headers` so a reverse-proxy misconfiguration cannot silently hand writable kitchen access to an unauthenticated attacker spoofing `Remote-User` headers.

**Architecture:** A new `FamilyRecipes::TrustedProxyConfig` value object parses four env vars at boot: `TRUSTED_PROXY_IPS` (CIDR allowlist, default `127.0.0.0/8,::1/128`) and `TRUSTED_HEADER_USER` / `_EMAIL` / `_NAME` (configurable header names, defaulting to `Remote-*`). An initializer loads it into `Rails.configuration.trusted_proxy_config`. A second initializer emits a production-only `Rails.logger.warn` when the allowlist is still at the loopback default. `authenticate_from_headers` gains a per-request peer IP check — if the raw TCP peer (`request.env['REMOTE_ADDR']`, NOT `request.remote_ip` which is the XFF-walked, spoofable value) is not in the allowlist, trusted headers are ignored and the request falls through to anonymous. The README gets a rewrite of the auth section with trust model, underscore/dash footgun, and a "Disabling trusted-header auth" subsection.

**Tech Stack:** Rails 8, Minitest, `IPAddr` (stdlib), RuboCop, Brakeman. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-04-10-trusted-header-and-multi-kitchen-cleanup-design.md` (PR 2 section).

**Prerequisite:** PR 1 (`feature/drop-multi-kitchen`, #363) merged to `main`. This plan assumes you are starting from a clean `main` post-#363.

**Branch:** `feature/harden-trusted-header-auth` (created in Task 0).

---

## File Structure

**Files to create:**

- `lib/familyrecipes/trusted_proxy_config.rb` — frozen value object parsing env vars, exposing `allow?(ip_string)`, `user_header` / `email_header` / `name_header` (Rack env keys), and `default_networks?` for the warning
- `config/initializers/trusted_proxy.rb` — one-liner loader that sets `Rails.application.config.trusted_proxy_config = FamilyRecipes::TrustedProxyConfig.from_env`
- `config/initializers/trusted_proxy_warning.rb` — production-only startup warning
- `test/lib/familyrecipes/trusted_proxy_config_test.rb` — unit tests for the config class

**Files to modify:**

- `lib/familyrecipes.rb` — add `require_relative 'familyrecipes/trusted_proxy_config'`
- `app/controllers/application_controller.rb` — rewrite `authenticate_from_headers` to use the config + peer IP gate; update header comment
- `test/controllers/header_auth_test.rb` — add cases for peer IP allowlist and custom header names
- `README.md` — rewrite "Add authentication (production)" section and extend env var table

**Files NOT touched:**

- `app/models/kitchen.rb` — untouched by this PR
- `auto_join_sole_kitchen` inside `ApplicationController` — untouched (now protected by the new peer IP check on its caller)
- Rate limiting config — header auth is not brute-forceable, existing limits on `/new` and `/join` are sufficient
- `config/puma.rb` — not inspected at runtime; the warning uses `Rails.env.production?` + `default_networks?` instead

---

## Task 0: Branch from main

**Files:** none

- [ ] **Step 1: Confirm `main` is at the merged #363 commit**

Run:
```bash
git checkout main
git pull
git log -1 --oneline
```

Expected: HEAD is the squash-merge commit of PR #363 (or later). If PR #363 has not been merged yet, STOP and merge it first — this plan depends on the post-#363 state (no `with_multi_kitchen`, no `MULTI_KITCHEN` env var references).

- [ ] **Step 2: Create the feature branch**

Run:
```bash
git checkout -b feature/harden-trusted-header-auth
```

Expected: `Switched to a new branch 'feature/harden-trusted-header-auth'`.

---

## Task 1: Create `TrustedProxyConfig` with unit tests (TDD)

**Files:**
- Create: `test/lib/familyrecipes/trusted_proxy_config_test.rb`
- Create: `lib/familyrecipes/trusted_proxy_config.rb`
- Modify: `lib/familyrecipes.rb`

Write the tests first, verify they fail with a clear `NameError`, then implement the class. The config is a pure value object — no Rails dependency — so the tests load only `ipaddr` and `active_support/core_ext/object/blank` for `blank?`.

- [ ] **Step 1: Write the failing unit tests**

Create `test/lib/familyrecipes/trusted_proxy_config_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class TrustedProxyConfigTest < ActiveSupport::TestCase
  Config = FamilyRecipes::TrustedProxyConfig

  test 'from_env uses loopback default when TRUSTED_PROXY_IPS is unset' do
    cfg = Config.from_env({})

    assert cfg.allow?('127.0.0.1')
    assert cfg.allow?('127.5.5.5')
    assert cfg.allow?('::1')
    assert_not cfg.allow?('10.0.0.1')
    assert_not cfg.allow?('203.0.113.5')
    assert_predicate cfg, :default_networks?
  end

  test 'from_env parses comma-separated CIDR list with whitespace tolerance' do
    cfg = Config.from_env('TRUSTED_PROXY_IPS' => '10.0.0.0/24, 192.168.1.0/24 ,172.16.0.0/16')

    assert cfg.allow?('10.0.0.5')
    assert cfg.allow?('192.168.1.200')
    assert cfg.allow?('172.16.5.5')
    assert_not cfg.allow?('127.0.0.1')
    assert_not cfg.default_networks?
  end

  test 'from_env parses IPv6 CIDRs' do
    cfg = Config.from_env('TRUSTED_PROXY_IPS' => 'fd00::/8')

    assert cfg.allow?('fd12:3456::1')
    assert_not cfg.allow?('2001:db8::1')
  end

  test 'from_env with empty TRUSTED_PROXY_IPS string produces empty allowlist' do
    cfg = Config.from_env('TRUSTED_PROXY_IPS' => '')

    assert_not cfg.allow?('127.0.0.1')
    assert_not cfg.allow?('10.0.0.1')
    assert_not cfg.default_networks?
  end

  test 'allow? returns false for blank input' do
    cfg = Config.from_env({})

    assert_not cfg.allow?(nil)
    assert_not cfg.allow?('')
  end

  test 'allow? returns false for malformed IP strings' do
    cfg = Config.from_env({})

    assert_not cfg.allow?('not-an-ip')
    assert_not cfg.allow?('999.999.999.999')
  end

  test 'header name env vars map to Rack env keys with HTTP_ prefix and underscores' do
    cfg = Config.from_env(
      'TRUSTED_HEADER_USER' => 'X-Webauth-User',
      'TRUSTED_HEADER_EMAIL' => 'X-Webauth-Email',
      'TRUSTED_HEADER_NAME' => 'X-Webauth-Name'
    )

    assert_equal 'HTTP_X_WEBAUTH_USER', cfg.user_header
    assert_equal 'HTTP_X_WEBAUTH_EMAIL', cfg.email_header
    assert_equal 'HTTP_X_WEBAUTH_NAME', cfg.name_header
  end

  test 'header name defaults map to Remote-* Rack env keys' do
    cfg = Config.from_env({})

    assert_equal 'HTTP_REMOTE_USER', cfg.user_header
    assert_equal 'HTTP_REMOTE_EMAIL', cfg.email_header
    assert_equal 'HTTP_REMOTE_NAME', cfg.name_header
  end

  test 'invalid CIDR raises InvalidConfigError with a clear message' do
    error = assert_raises(Config::InvalidConfigError) do
      Config.from_env('TRUSTED_PROXY_IPS' => '10.0.0.0/99')
    end

    assert_match(/TRUSTED_PROXY_IPS/, error.message)
  end

  test 'default_networks? is true only when TRUSTED_PROXY_IPS matches the default verbatim' do
    assert_predicate Config.from_env({}), :default_networks?
    assert_predicate Config.from_env('TRUSTED_PROXY_IPS' => Config::DEFAULT_NETWORKS), :default_networks?
    assert_not_predicate Config.from_env('TRUSTED_PROXY_IPS' => '127.0.0.0/8'), :default_networks?
  end
end
```

- [ ] **Step 2: Run the failing tests**

Run: `ruby -Itest test/lib/familyrecipes/trusted_proxy_config_test.rb`

Expected: `NameError: uninitialized constant FamilyRecipes::TrustedProxyConfig` or similar. This confirms the tests are reaching the class lookup and there is nothing defined yet.

- [ ] **Step 3: Implement `TrustedProxyConfig`**

Create `lib/familyrecipes/trusted_proxy_config.rb`:

```ruby
# frozen_string_literal: true

require 'ipaddr'

# Frozen config for trusted-header auth, parsed once from env vars at boot.
# Exposes a per-request peer IP check (allow?) and the Rack env keys for
# the configured header names. Built by a Rails initializer and read by
# ApplicationController#authenticate_from_headers — the controller never
# touches ENV directly.
#
# Defense-in-depth model: even if the reverse proxy is misconfigured and
# leaks inbound Remote-User headers from external requests, the peer IP
# check ignores them unless the TCP peer is in the allowlist. The loopback
# default (127.0.0.0/8 + ::1/128) covers same-host docker-compose installs
# zero-config; multi-host operators opt in by setting TRUSTED_PROXY_IPS.
# Empty string disables trusted-header auth entirely.
#
# Collaborators:
# - ApplicationController#authenticate_from_headers: per-request caller
# - config/initializers/trusted_proxy.rb: boot-time loader
# - config/initializers/trusted_proxy_warning.rb: production warning gate
module FamilyRecipes
  class TrustedProxyConfig
    DEFAULT_NETWORKS = '127.0.0.0/8,::1/128'

    class InvalidConfigError < StandardError; end

    def self.from_env(env = ENV)
      networks_raw = env.fetch('TRUSTED_PROXY_IPS', DEFAULT_NETWORKS)
      new(
        networks: parse_networks(networks_raw),
        user_header_name: env.fetch('TRUSTED_HEADER_USER', 'Remote-User'),
        email_header_name: env.fetch('TRUSTED_HEADER_EMAIL', 'Remote-Email'),
        name_header_name: env.fetch('TRUSTED_HEADER_NAME', 'Remote-Name'),
        default_networks: networks_raw == DEFAULT_NETWORKS
      ).freeze
    end

    def self.parse_networks(raw)
      return [] if raw.strip.empty?

      raw.split(',').map { |s| IPAddr.new(s.strip) }
    rescue IPAddr::Error => error
      raise InvalidConfigError, "TRUSTED_PROXY_IPS contains invalid CIDR: #{error.message}"
    end

    attr_reader :user_header, :email_header, :name_header

    def initialize(networks:, user_header_name:, email_header_name:, name_header_name:, default_networks:)
      @networks = networks.freeze
      @user_header = to_env_key(user_header_name)
      @email_header = to_env_key(email_header_name)
      @name_header = to_env_key(name_header_name)
      @default_networks = default_networks
    end

    def allow?(ip_string)
      return false if ip_string.nil? || ip_string.empty?

      ip = IPAddr.new(ip_string)
      @networks.any? { |net| net.include?(ip) }
    rescue IPAddr::Error
      false
    end

    def default_networks?
      @default_networks
    end

    private

    def to_env_key(header_name)
      "HTTP_#{header_name.upcase.tr('-', '_')}"
    end
  end
end
```

- [ ] **Step 4: Wire the new file into the domain module loader**

In `lib/familyrecipes.rb`, add this line at the bottom of the `require_relative` list (after `require_relative 'familyrecipes/smart_tag_registry'`):

```ruby
require_relative 'familyrecipes/trusted_proxy_config'
```

- [ ] **Step 5: Run the unit tests — expect all pass**

Run: `ruby -Itest test/lib/familyrecipes/trusted_proxy_config_test.rb`

Expected: 10 runs, 10 passes, 0 failures. If a test fails, read the message and fix the implementation — do not modify the tests.

- [ ] **Step 6: Run the full test suite to confirm nothing else broke**

Run: `bundle exec rake test`

Expected: pre-existing test count + 10 new, all green.

- [ ] **Step 7: Run RuboCop**

Run: `bundle exec rake lint`

Expected: 0 offenses.

- [ ] **Step 8: Commit**

```bash
git add lib/familyrecipes.rb lib/familyrecipes/trusted_proxy_config.rb test/lib/familyrecipes/trusted_proxy_config_test.rb
git commit -m "Add TrustedProxyConfig for trusted-header auth

Part of #365. Pure value object: parses TRUSTED_PROXY_IPS (CIDR list
with a 127.0.0.0/8,::1/128 default) and TRUSTED_HEADER_USER/_EMAIL/_NAME
from the environment, exposes allow?(ip_string) for the per-request
peer check, and exposes Rack env keys for the configured header names.
Not yet wired into the controller.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Load the config at boot

**Files:**
- Create: `config/initializers/trusted_proxy.rb`

- [ ] **Step 1: Create the initializer**

Create `config/initializers/trusted_proxy.rb`:

```ruby
# frozen_string_literal: true

# Loads FamilyRecipes::TrustedProxyConfig once at boot from environment
# variables (TRUSTED_PROXY_IPS, TRUSTED_HEADER_USER/_EMAIL/_NAME) and
# stashes it on Rails.configuration so ApplicationController can read
# it without touching ENV directly. An invalid CIDR in TRUSTED_PROXY_IPS
# raises at boot — fail fast on operator typos.
Rails.application.config.trusted_proxy_config = FamilyRecipes::TrustedProxyConfig.from_env
```

- [ ] **Step 2: Run the full test suite — nothing should break**

Run: `bundle exec rake test`

Expected: all tests pass. The controller does not read `trusted_proxy_config` yet, so this is a no-op from a behavior standpoint. But Rails will evaluate the initializer on boot, which exercises the happy-path `from_env({})` call against the real ENV.

- [ ] **Step 3: Commit**

```bash
git add config/initializers/trusted_proxy.rb
git commit -m "Load TrustedProxyConfig at boot

Part of #365. Stashes the frozen config on Rails.configuration so
ApplicationController can read it without touching ENV directly.
Invalid CIDR in TRUSTED_PROXY_IPS now raises at boot (fail fast).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Rewrite `authenticate_from_headers` with the peer IP gate

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `test/controllers/header_auth_test.rb`

TDD: write the new integration tests first (they should fail for the right reasons), then rewrite the controller method, then watch them pass.

- [ ] **Step 1: Write the failing integration tests**

Open `test/controllers/header_auth_test.rb` and add these tests at the bottom of the class, before the closing `end`:

```ruby
  test 'ignores headers when peer IP is outside the allowlist' do
    assert_no_difference 'User.count' do
      assert_no_difference 'Session.count' do
        get kitchen_root_path(kitchen_slug: @kitchen.slug),
            headers: {
              'REMOTE_ADDR' => '203.0.113.5',
              'HTTP_REMOTE_USER' => 'mallory',
              'HTTP_REMOTE_NAME' => 'Mallory',
              'HTTP_REMOTE_EMAIL' => 'mallory@attacker.example'
            }
      end
    end

    assert_response :success
  end

  test 'honors headers when peer IP is inside the default loopback allowlist' do
    # ActionDispatch::IntegrationTest sets REMOTE_ADDR to 127.0.0.1 by default,
    # which is inside the loopback default. No override needed.
    assert_difference 'User.count', 1 do
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
        'HTTP_REMOTE_USER' => 'frank',
        'HTTP_REMOTE_NAME' => 'Frank',
        'HTTP_REMOTE_EMAIL' => 'frank@example.com'
      }
    end
  end

  test 'honors a custom header name when TRUSTED_HEADER_USER is configured' do
    stub_trusted_proxy_config(user_header_name: 'X-Webauth-User', email_header_name: 'X-Webauth-Email') do
      assert_difference 'User.count', 1 do
        get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
          'HTTP_X_WEBAUTH_USER' => 'grace',
          'HTTP_X_WEBAUTH_EMAIL' => 'grace@example.com'
        }
      end
    end

    assert_predicate User.find_by(email: 'grace@example.com'), :present?
  end

  test 'ignores the default Remote-User header when a custom header name is configured' do
    stub_trusted_proxy_config(user_header_name: 'X-Webauth-User') do
      assert_no_difference 'User.count' do
        get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: {
          'HTTP_REMOTE_USER' => 'heidi',
          'HTTP_REMOTE_EMAIL' => 'heidi@example.com'
        }
      end
    end
  end

  private

  def stub_trusted_proxy_config(**overrides)
    original = Rails.application.config.trusted_proxy_config
    env = {
      'TRUSTED_HEADER_USER' => overrides[:user_header_name] || 'Remote-User',
      'TRUSTED_HEADER_EMAIL' => overrides[:email_header_name] || 'Remote-Email',
      'TRUSTED_HEADER_NAME' => overrides[:name_header_name] || 'Remote-Name'
    }
    Rails.application.config.trusted_proxy_config = FamilyRecipes::TrustedProxyConfig.from_env(env)
    yield
  ensure
    Rails.application.config.trusted_proxy_config = original
  end
```

Note: the `stub_trusted_proxy_config` helper is private on the test class so it's only visible inside this file. It swaps in a fresh config, yields, and restores the original in `ensure` — safe against test failures.

- [ ] **Step 2: Run the header auth tests — the new ones should fail**

Run: `ruby -Itest test/controllers/header_auth_test.rb`

Expected: the new tests fail with assertions because `authenticate_from_headers` still uses hardcoded `HTTP_REMOTE_USER` and no peer IP check. Specifically:

- "ignores headers when peer IP is outside the allowlist" — fails because `User.count` increments (a user gets created from the spoofed header)
- "honors headers when peer IP is inside the default loopback allowlist" — PASSES already (existing behavior accepts headers)
- "honors a custom header name" — fails because the controller reads `HTTP_REMOTE_USER`, not `HTTP_X_WEBAUTH_USER`
- "ignores the default Remote-User header when a custom header name is configured" — fails because the controller still reads `HTTP_REMOTE_USER`

Existing tests in the file continue to pass.

- [ ] **Step 3: Rewrite `authenticate_from_headers` in `app/controllers/application_controller.rb`**

Find the method at lines 72–89:

```ruby
  def authenticate_from_headers
    return if authenticated?

    # Must use request.env, not request.headers — 'Remote-User' collides with
    # the CGI REMOTE_USER variable, so request.headers['Remote-User'] is unreliable.
    remote_user = request.env['HTTP_REMOTE_USER']
    return if remote_user.blank?

    email = request.env['HTTP_REMOTE_EMAIL'].presence || "#{remote_user}@header.local"
    name = request.env['HTTP_REMOTE_NAME'].presence || remote_user

    user = User.find_or_create_by!(email: email) do |u|
      u.name = name
    end

    start_new_session_for(user)
    auto_join_sole_kitchen(user)
  end
```

Replace with:

```ruby
  def authenticate_from_headers
    return if authenticated?

    cfg = Rails.application.config.trusted_proxy_config
    return unless cfg.allow?(request.env['REMOTE_ADDR'])

    # Must use request.env, not request.headers — 'Remote-User' collides with
    # the CGI REMOTE_USER variable, so request.headers['Remote-User'] is unreliable.
    remote_user = request.env[cfg.user_header]
    return if remote_user.blank?

    email = request.env[cfg.email_header].presence || "#{remote_user}@header.local"
    name = request.env[cfg.name_header].presence || remote_user

    user = User.find_or_create_by!(email: email) do |u|
      u.name = name
    end

    start_new_session_for(user)
    auto_join_sole_kitchen(user)
  end
```

Changes: load the config once, peer gate on line 2 (reads the raw TCP peer from `request.env['REMOTE_ADDR']` — NOT `request.remote_ip`, which is the XFF-walked value and spoofable from any RFC1918 host), read the three headers via the configured Rack env keys. Everything else (user creation, session start, auto-join) unchanged.

**Why `REMOTE_ADDR` and not `request.remote_ip`:** `ActionDispatch::RemoteIp` walks the `X-Forwarded-For` chain past Rails' default trusted-proxies list, which includes all RFC1918 ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `fc00::/7`, etc.). Any host on a private network could forge `X-Forwarded-For: 127.0.0.1` and `request.remote_ip` would return the spoofed loopback, bypassing the allowlist. `REMOTE_ADDR` is the raw TCP peer — the actual host that opened the socket — and cannot be spoofed by any HTTP header. A regression test in `test/controllers/header_auth_test.rb` locks this in.

- [ ] **Step 4: Update the `ApplicationController` header comment**

Find the existing header comment (lines 1–22). Replace the trusted-header section. The current version reads:

```ruby
# Central before_action pipeline: resume session → authenticate from trusted
# headers (Authelia in production) → auto-login in dev → set tenant from path.
# Public reads are allowed (allow_unauthenticated_access); write paths and
# member-only pages call require_membership. Also manages the optional
# kitchen_slug URL scope and cache headers for member-only pages.
#
# Trusted-header auto-join: when trusted headers identify a brand-new user
# (zero memberships) and exactly one Kitchen exists, the user is auto-joined
# to that kitchen as a member. This smooths homelab onboarding under Authelia,
# where the reverse proxy is the source of truth for identity. Trust model:
# the proxy MUST strip any inbound Remote-User/Remote-Email headers from
# external requests — if the proxy is misconfigured, an attacker spoofing
# headers would gain membership in the sole kitchen. The narrow condition
# (exactly one kitchen) limits blast radius so multi-kitchen installs are
# unaffected.
#
# Collaborators:
# - Authentication concern: session lifecycle (resume, start, terminate)
# - Kitchen / acts_as_tenant: multi-tenant scoping via set_current_tenant
# - User / Membership: trusted-header user lookup and auto-join
```

Replace with:

```ruby
# Central before_action pipeline: resume session → authenticate from trusted
# headers (Authelia, Authentik, oauth2-proxy, etc.) → auto-login in dev →
# set tenant from path. Public reads are allowed (allow_unauthenticated_access);
# write paths and member-only pages call require_membership. Also manages
# the optional kitchen_slug URL scope and cache headers for member-only pages.
#
# Trusted-header auth (defense in depth): every request that carries the
# configured Remote-User header is subject to a per-request check of the
# raw TCP peer (request.env['REMOTE_ADDR'], NOT request.remote_ip which
# is the XFF-walked value and spoofable from any RFC1918 host) against
# Rails.configuration.trusted_proxy_config. If the peer is not in the
# allowlist (default: 127.0.0.0/8, ::1/128) the headers are ignored and
# the request falls through to anonymous/passwordless. This protects
# against reverse-proxy misconfigurations that leak inbound Remote-*
# headers from external requests. Operators running a proxy on a separate
# host or different docker network must widen the allowlist via
# TRUSTED_PROXY_IPS; operators who cannot guarantee header stripping can
# disable the path entirely with TRUSTED_PROXY_IPS= (empty). See README
# "Disabling trusted-header auth".
#
# Trusted-header auto-join: when trusted headers identify a brand-new user
# (zero memberships) and exactly one Kitchen exists, the user is auto-joined
# to that kitchen as a member. Restricted by the peer gate above.
#
# Collaborators:
# - Authentication concern: session lifecycle (resume, start, terminate)
# - FamilyRecipes::TrustedProxyConfig: peer IP + header name resolution
# - Kitchen / acts_as_tenant: multi-tenant scoping via set_current_tenant
# - User / Membership: trusted-header user lookup and auto-join
```

- [ ] **Step 5: Run the header auth tests — all should pass**

Run: `ruby -Itest test/controllers/header_auth_test.rb`

Expected: all tests pass, including the four new ones added in Step 1. If a test still fails, read the failure and fix the controller — do not modify the tests unless you identify a genuine test bug.

- [ ] **Step 6: Run the full test suite**

Run: `bundle exec rake test`

Expected: all tests pass.

- [ ] **Step 7: Run RuboCop**

Run: `bundle exec rake lint`

Expected: 0 offenses.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/application_controller.rb test/controllers/header_auth_test.rb
git commit -m "Add per-request peer IP check to trusted-header auth

Part of #365. authenticate_from_headers now reads from the
TrustedProxyConfig stash on Rails.configuration: first gating on
the raw TCP peer (request.env['REMOTE_ADDR']) against the allowlist,
then reading the three headers via the configured Rack env keys
(instead of hardcoded HTTP_REMOTE_USER). Headers from a
non-allowlisted peer are ignored;
the request falls through to anonymous. Custom header names work
for Authentik, oauth2-proxy, Grafana, and Caddy forward_auth users.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Add the production startup warning

**Files:**
- Create: `config/initializers/trusted_proxy_warning.rb`

The warning is production-only, fires once at boot via `Rails.logger.warn`, and is gated on `default_networks?`. Development and test are silent.

- [ ] **Step 1: Create the initializer**

Create `config/initializers/trusted_proxy_warning.rb`:

```ruby
# frozen_string_literal: true

# Production-only startup nudge for operators running with the default
# loopback-only trusted-proxy allowlist. If the reverse proxy is on the
# same host / same container, loopback is correct and this warning is
# noise you can ignore. If the proxy is on a separate host or a
# different docker network, the default ignores trusted headers from
# your proxy — you need to set TRUSTED_PROXY_IPS to the proxy's CIDR.
#
# Does not hard-fail boot: there are too many valid topologies to guess
# a safe universal default. Does not fire in development or test.
# See README "Trust model" for the full hardening story.
if Rails.env.production? && Rails.application.config.trusted_proxy_config.default_networks?
  Rails.logger.warn(
    'TRUSTED_PROXY_IPS is at the loopback-only default (127.0.0.0/8,::1/128). ' \
    'If your reverse proxy is not on the same host, set TRUSTED_PROXY_IPS to ' \
    "the proxy's CIDR range(s). To disable trusted-header auth entirely, set " \
    'TRUSTED_PROXY_IPS= (empty). See README for details.'
  )
end
```

- [ ] **Step 2: Verify development/test boot is silent**

Run: `bundle exec rake test`

Expected: all tests pass, no stray warning lines in the test output (beyond any pre-existing ones). The warning block is gated on `Rails.env.production?`, so it never fires in test.

- [ ] **Step 3: Verify the warning fires in simulated production**

Run:
```bash
RAILS_ENV=production SECRET_KEY_BASE=dummy bundle exec rails runner "puts 'booted'" 2>&1 | grep -i trusted_proxy_ips
```

Expected: the grep matches the warning line. If the command fails with a database or env error, that's expected in a non-production setup; the goal is to see the initializer run before the failure. If needed, substitute a one-line runner that exits immediately after initializer evaluation (`rails runner "exit 0"`).

If the grep returns nothing, the warning is silently failing — debug by temporarily adding `puts` to the initializer.

- [ ] **Step 4: Run the full test suite once more**

Run: `bundle exec rake test`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add config/initializers/trusted_proxy_warning.rb
git commit -m "Warn in production when trusted-proxy allowlist is at default

Part of #365. Rails.logger.warn at boot when Rails.env.production? and
TRUSTED_PROXY_IPS is unset/default. Silent in dev and test. Does not
hard-fail boot — too many valid topologies to guess a safe default.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Rewrite the README auth section

**Files:**
- Modify: `README.md`

Full rewrite of the "Add authentication (production)" section (currently lines 130–153) plus four new rows in the env var table above it (currently around line 123).

- [ ] **Step 1: Extend the env var table**

Find the env var table at approximately lines 123–128 of `README.md`:

```markdown
| Variable | Default | Description |
|---|---|---|
| `SECRET_KEY_BASE` | auto-generated | Rails session encryption key |
| `ALLOWED_HOSTS` | allow all | Comma-separated domain(s) for DNS rebinding protection |
| `RAILS_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |
| `USDA_API_KEY` | — | Free at [fdc.nal.usda.gov](https://fdc.nal.usda.gov/api-key-signup) |
```

Add four rows at the bottom:

```markdown
| `TRUSTED_PROXY_IPS` | `127.0.0.0/8,::1/128` | CIDR allowlist of reverse proxies allowed to set trusted-auth headers. Empty string disables trusted-header auth entirely. See "Trust model" below. |
| `TRUSTED_HEADER_USER` | `Remote-User` | HTTP header carrying the username/identifier from your reverse proxy. |
| `TRUSTED_HEADER_EMAIL` | `Remote-Email` | HTTP header carrying the user's email. |
| `TRUSTED_HEADER_NAME` | `Remote-Name` | HTTP header carrying the user's display name. |
```

- [ ] **Step 2: Rewrite the "Add authentication (production)" section**

Find the section at approximately lines 130–153 of `README.md`. The current content is:

```markdown
### 4. Add authentication (production)

familyrecipes is designed for deployment behind a reverse proxy with
trusted-header authentication ([Authelia](https://www.authelia.com/),
[Authentik](https://goauthentik.io/), etc.). The proxy sets `Remote-User`,
`Remote-Email`, and `Remote-Name` headers; the app reads them to identify
users and establish sessions.

Example [Caddy](https://caddyserver.com/) configuration:

```
recipes.example.com {
    forward_auth authelia:9091 {
        uri /api/authz/forward-auth
        copy_headers Remote-User Remote-Email Remote-Name Remote-Groups
    }
    reverse_proxy familyrecipes-app:3030
}
```

The app expects `X-Forwarded-Proto: https` from the proxy (Caddy sends this by
default). Without a TLS-terminating proxy, `force_ssl` causes a redirect loop.
The `/up` health endpoint is excluded from SSL redirect and host checks.
```

Replace the entire section (from `### 4. Add authentication (production)` through the `/up` sentence) with:

~~~markdown
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
~~~

(The `~~~` fences in this plan wrap the README insertion because the content itself contains `` ``` `` fences; when editing the README, use literal triple-backtick fences as usual.)

- [ ] **Step 3: Verify markdown renders cleanly**

Open `README.md` in a markdown preview (VS Code: Cmd-Shift-V; or push to a local branch and view on GitHub). Check: no broken fences, code blocks render, the header hierarchy is consistent with surrounding sections (H3 for the section, H4 for sub-sections), link targets are valid.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Rewrite README auth section for hardened trusted-header auth

Part of #365. New section covers: passwordless + trusted-header as
parallel paths, the explicit trust model and peer IP allowlist,
the underscore/dash header footgun, Caddy config with explicit header
strip rules, custom header names for non-Authelia proxies, and a
dedicated 'Disabling trusted-header auth' subsection with the
TRUSTED_PROXY_IPS= empty-string escape hatch. Env var table extended
with four new rows.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Final verification

**Files:** none modified

- [ ] **Step 1: Full test suite**

Run: `bundle exec rake test`

Expected: all tests pass. ~1971 runs (pre-#365 baseline + 10 new unit tests + 4 new integration tests).

- [ ] **Step 2: Lint**

Run: `bundle exec rake lint`

Expected: 0 offenses.

- [ ] **Step 3: Brakeman**

Run: `bundle exec rake security`

Expected: no new warnings. If Brakeman flags `authenticate_from_headers` as a new finding, double-check the peer IP gate — the whole point of this PR is to make that method safer, not introduce a new smell.

- [ ] **Step 4: Release audit (full)**

Run: `bin/dev` in a separate terminal, then in this terminal: `bundle exec rake release:audit:full`

Expected: Tier 2 checks pass, Tier 3 security Playwright specs pass. The security specs in `test/security/*.spec.mjs` run against the dev server on `127.0.0.1:3030`, which is inside the default allowlist, so existing behavior is preserved.

Stop the dev server when done.

- [ ] **Step 5: Manual smoke test — default allowlist accepts loopback**

With the dev server running (`bin/dev`), from the same host:

```bash
curl -s -H 'Remote-User: smoke' -H 'Remote-Name: Smoke Test' -H 'Remote-Email: smoke@test.local' http://rika:3030/ -o /dev/null -w '%{http_code}\n'
```

Expected: `200`. Then verify in a Rails console (`bin/rails c`):

```ruby
User.find_by(email: 'smoke@test.local')
```

Expected: a user record. Clean up: `User.find_by(email: 'smoke@test.local')&.destroy`.

- [ ] **Step 6: Manual smoke test — empty allowlist disables trusted-header auth**

Stop the dev server. Set the env var to empty and restart:

```bash
TRUSTED_PROXY_IPS= bin/dev
```

From the same host:

```bash
curl -s -H 'Remote-User: blocked' -H 'Remote-Name: Blocked' -H 'Remote-Email: blocked@test.local' http://rika:3030/ -o /dev/null -w '%{http_code}\n'
```

Expected: `200` (the landing page is public). But in Rails console:

```ruby
User.find_by(email: 'blocked@test.local')
```

Expected: `nil`. The headers were ignored because the peer IP check rejected every request (empty allowlist).

Stop the dev server. Clean up the env var and restart for normal use.

- [ ] **Step 7: Manual smoke test — custom header name works**

Start the dev server with a custom header name:

```bash
TRUSTED_HEADER_USER=X-Webauth-User TRUSTED_HEADER_EMAIL=X-Webauth-Email bin/dev
```

Request with the custom header:

```bash
curl -s -H 'X-Webauth-User: customheader' -H 'X-Webauth-Email: custom@test.local' http://rika:3030/ -o /dev/null -w '%{http_code}\n'
```

Rails console:

```ruby
User.find_by(email: 'custom@test.local')
```

Expected: a user record. Clean up: `User.find_by(email: 'custom@test.local')&.destroy`.

Then verify the default header name is now ignored:

```bash
curl -s -H 'Remote-User: defaulter' -H 'Remote-Email: defaulter@test.local' http://rika:3030/ -o /dev/null -w '%{http_code}\n'
```

Rails console:

```ruby
User.find_by(email: 'defaulter@test.local')
```

Expected: `nil`. The default `Remote-User` header was ignored because `TRUSTED_HEADER_USER` was pointing at `X-Webauth-User`.

Stop the dev server.

- [ ] **Step 8: Push the branch and open the PR**

```bash
git push -u origin feature/harden-trusted-header-auth
gh pr create --title "Harden trusted-header auth with peer IP allowlist (#365)" --body "$(cat <<'EOF'
## Summary

- `authenticate_from_headers` now performs a per-request peer IP check
  via `FamilyRecipes::TrustedProxyConfig` before honoring `Remote-*`
  headers. Default allowlist is `127.0.0.0/8,::1/128` (Gitea pattern)
  so same-host docker-compose installs keep working zero-config.
- Trusted header names are configurable via `TRUSTED_HEADER_USER` /
  `_EMAIL` / `_NAME` for Authentik, oauth2-proxy, Grafana, and Caddy
  `forward_auth` users.
- Production startup warning when the allowlist is still at default
  (`Rails.logger.warn`, silent in dev/test, does not hard-fail boot).
- README "Add authentication (production)" section rewritten with
  explicit trust model, the underscore/dash header footgun, Caddy
  config with header strip rules, and a "Disabling trusted-header
  auth" subsection (`TRUSTED_PROXY_IPS=` empty-string escape hatch).

Spec: `docs/superpowers/specs/2026-04-10-trusted-header-and-multi-kitchen-cleanup-design.md` (PR 2 section). Follows the Gitea pattern documented in spec research — every header-spoofing CVE in the wild comes from projects that trusted headers without a peer IP check.

Resolves #365.

## Test plan

- [ ] `bundle exec rake test` — full suite green, includes 10 new
      `TrustedProxyConfig` unit tests + 4 new header auth integration tests
- [ ] `bundle exec rake lint` — 0 offenses
- [ ] `bundle exec rake security` — no new Brakeman findings
- [ ] `bundle exec rake release:audit:full` — Tier 2 + Tier 3 green
- [ ] Manual: default allowlist accepts loopback curl
- [ ] Manual: `TRUSTED_PROXY_IPS=` (empty) disables trusted-header auth
- [ ] Manual: custom `TRUSTED_HEADER_USER` accepts the configured header
      and ignores the default `Remote-User`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review Notes

**Spec coverage:**
- `TRUSTED_PROXY_IPS` env var with loopback default → Task 1 + Task 2 ✓
- `TRUSTED_HEADER_USER` / `_EMAIL` / `_NAME` configurable → Task 1 + Task 3 ✓
- Per-request peer IP check → Task 3 ✓
- Startup warning in production → Task 4 ✓
- Unit tests for `TrustedProxyConfig` → Task 1 ✓
- Integration tests for peer IP gate + custom headers → Task 3 ✓
- README rewrite with trust model, underscore footgun, disable subsection → Task 5 ✓
- `ApplicationController` header comment update → Task 3 Step 4 ✓
- `rake test` clean, `rake lint` clean, `rake security` clean → Task 6 ✓
- Empty `TRUSTED_PROXY_IPS` disables (not unset) → covered by unit test in Task 1 and manual smoke test in Task 6 ✓

**Type consistency check:**
- `FamilyRecipes::TrustedProxyConfig` — used consistently across Tasks 1–4
- `cfg.allow?(ip_string)` — signature consistent in Task 1 (definition), Task 3 (controller usage), Task 3 (integration tests)
- `cfg.user_header` / `.email_header` / `.name_header` — Rack env key strings (`HTTP_...`), consistent across definition and usage
- `cfg.default_networks?` — used in Task 1 (test) and Task 4 (warning gate)
- `Rails.application.config.trusted_proxy_config` — same accessor in Task 2 (assignment), Task 3 (read), Task 3 (test helper swap), Task 4 (warning read)
- `InvalidConfigError` — defined in Task 1, tested in Task 1, behavior documented in Task 2's commit message

**Risk watch:**
- Task 3 test helper `stub_trusted_proxy_config` swaps global state. The `ensure` block restores it even on test failure. This is correct for Minitest (not Rails system tests or parallel tests where shared state would be a problem).
- Task 4 Step 3 production-warning verification is slightly fragile — the `rails runner` under `RAILS_ENV=production` may fail on database config. If it does, the fallback is to read the initializer code and trust it visually. The unit tests for `default_networks?` already prove the gate logic.
