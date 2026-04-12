# Mirepoix Orientation

*Strategic orientation for the homelab-to-hosted transition. Commits to
direction; defers implementation.*

## Purpose

This doc is the north star for where Mirepoix (née Family Recipes) is headed
over the next 6–12 months. It exists because the `feature/auth` and Phase 2
magic-link merges settled a lot of tactical questions but left the
*strategic* posture implicit, and implicit strategy breeds overwhelm.

Read this when you feel lost. It tells you:

- What's already decided (don't re-open these)
- What's deferred and why (don't panic about them)
- What's next (a concrete slice you can execute)
- What triggers the next phase (so you stop worrying about when)

## §1. Current phase snapshot

- **Phase 1** — join codes, kitchen creation, session auth. **Shipped**
  (PR #368, 2026-04-10).
- **Phase 2** — magic-link auth, trusted-header removal, Fly.io-*ready*
  code. **Shipped** (PR #375, 2026-04-11). Collapsed the old Phase 2 + 3
  into one.
- **Phase 3** — open `/new` on hosted for self-serve kitchen creation.
  **Not started.** Trivial code extension per the Phase 2 spec (add
  `new_kitchen` to `MagicLink#purpose`, branch in the consume path).
  Scope and triggers in §4.
- **Phase 4** — passkeys, OAuth, billing, admin dashboard, `Gemfile.saas`
  split. **Not planned.** Listed so the map doesn't cliff. Shape in §5.

**Authoritative phase plan:** `docs/superpowers/specs/2026-04-10-magic-link-auth-design.md`,
"Phasing Going Forward" section. The earlier three-phase outline in
`2026-04-08-auth-system-design.md` is **superseded**; see §7.

## §2. Strategic commitments

Things committed to and not re-opened every month:

- **Product name.** Migrating from *Family Recipes* to **Mirepoix**. Domain
  `mirepoix.recipes` already registered at Porkbun. Rebrand is a pre-deploy
  prerequisite; it touches the Rails app module, working directory, Docker
  image name, LICENSE, CLAUDE.md, and docs. Earns its own implementation
  plan. See §3 punch list.
- **Product posture.** Free self-hosted + future paid SaaS. Fizzy shape.
- **Ideological anchor.** 37signals-adjacent. Kamal for deploy, Rails
  conventions first, server-rendered Hotwire, SQLite by default.
- **License.** **O'Saasy** (osaasy.dev) — MIT-ish with SaaS rights reserved
  for the copyright holder. Apply at the rebrand. Not OSI-approved;
  accepted tradeoff because the audience is Docker/homelab operators, not
  distro packagers.
- **Deploy target.** **Kamal on a managed VPS** (Hetzner Cloud preferred,
  DO/Linode acceptable). Thruster for TLS. **Not Fly.io.** Rationale:
  37signals-aligned, skill transfers to Phase 4, predictable cost,
  conceptually adjacent to existing homelab practice.
- **Auth.** Magic link is the sole path. Trusted-header auth is not coming
  back absent a concrete operator pain the Phase 2 spec didn't anticipate.
- **Database.** SQLite. Postgres only if we hit a concrete scale pain (we
  are nowhere close).

## §3. Near-term slice: dogfood off LAN

The concrete bill of materials to move Mirepoix off your LAN and onto a
public host for you, your family, and the occasional invited friend.

### Infrastructure

- **VPS:** Hetzner Cloud **CX22** (2 vCPU, 4GB, 40GB SSD, ~$5/mo),
  **Ashburn, VA** (US-East, closest to Alexandria, VA).
- **OS:** Ubuntu 24.04 LTS (Kamal default).
- **Domain:** `mirepoix.recipes` at Porkbun. A record to VPS public IP.

### Deployment

- **Kamal 2.x** — single server, single role, one `config/deploy.yml`.
  Starting point: adapt Fizzy's `config/deploy.yml`.
- **Docker image:** existing GHCR image, renamed as part of the rebrand.
- **TLS:** Thruster + Let's Encrypt via `TLS_DOMAIN=mirepoix.recipes`. Zero
  certbot dance.
- **Secrets:** 1Password-only, via Kamal's 1Password adapter. All secrets
  (Rails master key, ActiveRecord encryption keys, SMTP creds, API keys,
  backup creds) live in a "Mirepoix Production" 1Password vault. **Delete
  `config/credentials.yml.enc` + `config/master.key`** as part of the
  rebrand — Rails credentials adds ceremony without value when everything
  is already in 1Password. App reads all secrets via `ENV["FOO"]`; no
  `Rails.application.credentials.*` calls anywhere. Kamal's `op` CLI runs
  on the deploy machine (laptop), not the VPS — secrets are fetched at
  deploy time and pushed to the container as env vars.

### Email

- **Provider:** **Resend free tier** (3k emails/month). Magic link sends
  ~1 email per sign-in — free tier covers thousands of sessions.
- **DNS:** SPF + DKIM records at Porkbun. Resend provides exact values.
- **Sender:** `no-reply@mirepoix.recipes`.
- **Upgrade path:** Postmark ($15/mo) if deliverability becomes a concern.

### Data persistence

- **SQLite volume:** Docker named volume at `/rails/storage` — DB, Active
  Storage blobs, encryption keys. Kamal persists across deploys.
- **Backups:** **restic** to **Backblaze B2** via cron on the VPS. Daily
  snapshots, weekly pruning. ~$0.005/GB/mo — effectively free.
- **Backup testing:** **monthly** restore-to-scratch-volume dry run.
  *Untested backups aren't backups.* Non-negotiable.

### Observability

- **Logs:** `kamal app logs -f`.
- **Uptime:** Betterstack free tier. 10 monitors, 3-minute interval,
  email/Slack alerts.
- **Errors:** Skip Sentry for dogfood. Revisit at Phase 3.

### How friends join (soft beta answer)

Per the Phase 2 spec: `DISABLE_SIGNUPS=true`. Each new friend's kitchen is
seeded manually over SSH:

```bash
kamal app exec --interactive \
  "bin/rake 'kitchen:create[Smith Family,friend@example.com,Friend]'"
```

Share the printed join code by hand. Zero new-kitchen attack surface; you
are the bottleneck on growth, which at this scale is a feature. If this
gets annoying, that's the trigger for Phase 3 — not a guess.

### Operational hygiene

- `unattended-upgrades` for OS patches (one-time apt install at bootstrap)
- Hetzner Cloud Firewall (free): 22/80/443 only
- SSH: key-only auth, root login disabled
- No 24×7 monitoring, no pager, no runbook. It's dogfood.

### Pre-deploy punch list

Tracked in the pinned **"Kamal Deploy: Critical Path"** issue (#391) in the
`Kamal Deploy` milestone. That issue is the single source of truth for
what's left before first deploy — don't maintain a competing checklist
here.

Completed prior to this change: rebrand (#378), O'Saasy license (#379),
CLAUDE.md sweep, MEMORY.md update, superseded spec annotation.

### Explicitly NOT in this slice

Status page, incident response, DPAs, GDPR docs, Postgres migration,
multi-region failover, admin dashboard, billing, rate-limit tuning for real
abuse.

## §4. Phase 3 triggers

Phase 3 = open `/new` on hosted for self-serve kitchen creation. Trivial to
ship, but not appropriate now. It ships when at least **one** of these
triggers fires:

1. **Operational friction.** 10+ manually-seeded kitchens. If you're making
   coffee while seeding the 11th, it's time.
2. **Explicit willingness to pay.** Someone says *"I would pay for this."*
   Even if you don't accept payment yet, the signal is real and unblocks
   Phase 4 conversation.
3. **Time-boxed revisit.** Three months after first deploy. Dogfood without
   a review date ossifies.

And **all** gating requirements hold:

- Zero production data-loss incidents in the prior 30 days
- At least one *successfully restored* backup
- `rake release:audit:full` clean
- Abuse plan reviewed: rate-limit tuning + optional Cloudflare Turnstile
  scoped

**Scope when it happens** (outline only; becomes its own spec):

- `new_kitchen` value added to `MagicLink#purpose` enum
- `MagicLinksController#create` branches to create Kitchen + Membership on
  consume
- `KitchensController#new` gated on magic-link-consumed state, not
  `Kitchen.accepting_signups?`
- Stricter rate limit for `/new`
- Optional Cloudflare Turnstile (free, no SDK, one script tag)
- Abuse handling: manual `rake kitchen:destroy[slug]` or admin view

**NOT in Phase 3:** billing, admin dashboard, approval queues, email
verification beyond the magic link we already have.

## §5. Phase 4 shape

Phase 4 is *if ever, probably years from now.* This section commits to
SHAPE, not timing — so future-you doesn't re-derive it under pressure.

**Product shape.** Single hosted instance at `mirepoix.recipes` (or
`app.mirepoix.recipes`), paid subscription. Self-hosted stays free forever
under O'Saasy. Same codebase.

**Pricing (sketch).** Free tier limited to N kitchens or R recipes; paid
tier unlimited. Stripe Checkout + Stripe Customer Portal — no custom
billing code. Per-kitchen pricing, not per-user, since the family is the
natural billing entity.

**Billing integration.** Stripe gem in the main `Gemfile`, guarded by
`if ENV["STRIPE_SECRET_KEY"]`. `Subscription` model, `has_one :subscription`
on `Kitchen`. Webhook controller for lifecycle events. Grace period →
read-only → suspend on payment failure.

**`Gemfile.saas` engine split.** Only if a license-incompatible dependency
emerges. Stripe, Sentry, Postmark are all MIT/Apache. **Default: no split.**
Revisit if forced.

**Admin dashboard.** Audits1984 engine at `/admin`, gated to a hardcoded
admin email list. Hand-rolled kitchen search, subscription state,
impersonation. Not before Phase 4.

**Things that would force a rethink.** Hosted-only license-incompatible
dependency, per-user pricing data beats per-kitchen, SOC2/GDPR compliance
asks, federated identity obsolesces magic links.

**NOT in Phase 4.** Mobile app, public API, team collaboration beyond
kitchens, white-label/reseller, plugin system.

## §6. Deferred decisions

Explicit "not now" with reasons:

- **Identity / User split.** Declined in the Phase 2 spec. `User` +
  `Membership` already models the same idea.
- **Postgres migration.** SQLite is fine for one-box Kamal deploys.
- **Passkeys, OAuth, Sign-in-with-Apple.** No concrete pain — magic link
  works.
- **Solid Queue / async mail delivery.** Synchronous `deliver_now` until we
  have an async job worth wiring.
- **Admin dashboard.** Rails console is enough at beta scale.
- **Billing and subscriptions.** Phase 4.
- **`Gemfile.saas` engine split.** Phase 4, possibly never.

## §7. Stale-decision cleanup

Action items triggered by adopting this doc:

- [ ] Close issue #374 ("Bring back MULTI_KITCHEN?") with *"done
  differently — see `Kitchen.accepting_signups?`"*
- [ ] Update `MEMORY.md` "Passwordless Auth Merged (2026-04-10)" section
  — remove the stale *"Trusted-header path stays as a parallel homelab
  front door"* line
- [ ] Add **"Superseded by"** header to
  `docs/superpowers/specs/2026-04-08-auth-system-design.md` pointing at
  the Phase 2 spec
- [ ] **Sweep CLAUDE.md for stale references** — trusted-header leftovers,
  old phase descriptions, superseded workflow notes
- [ ] Commit this orientation doc on the `feature/orientation-doc` branch
