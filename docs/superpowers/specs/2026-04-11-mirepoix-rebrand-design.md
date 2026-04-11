# Mirepoix Rebrand

*Mechanical rename of the "Family Recipes" product to "mirepoix" across
source, config, infrastructure, docs, and live state. Blocks everything
else in the pre-deploy punch list.*

## Purpose

The orientation doc
(`docs/superpowers/specs/2026-04-11-orientation-design.md`) commits to
migrating the product name from *Family Recipes* to **mirepoix** as the
first pre-deploy step. The domain `mirepoix.recipes` is already registered
at Porkbun. This spec captures the scope, commitments, and host-side steps
for that rename so the implementation plan is a mechanical translation of
an agreed design rather than a sequence of ad-hoc decisions.

Read this when:

- Starting the rebrand implementation (paired with the plan doc)
- Auditing whether a brand reference is in-scope or frozen
- Deciding whether a follow-up change belongs here or in a different
  punch list item

## §1. Scope commitments

Six design questions were resolved during brainstorming. The answers
constrain the rest of the spec.

### §1.1 Internal Ruby namespaces — full rename

Both `Familyrecipes` (Rails app module, `config/application.rb`) and
`FamilyRecipes` (domain parser module, `lib/familyrecipes.rb`) merge to
`Mirepoix`. The one-word brand removes the historical case-parallel
(`Familyrecipes` / `FamilyRecipes`) without collision: Ruby reopens
`module Mirepoix` in two places, the Rails app only declares
`Mirepoix::Application`, and the parser only declares `Mirepoix::Recipe`,
`Mirepoix::Step`, etc. No wrapper namespace (`Mirepoix::Parser::*`) is
introduced — the existing disambiguation between parser types and
ActiveRecord models (`Mirepoix::Recipe` vs `Recipe`) already works.

**Why not leave the parser alone?** Leaving `FamilyRecipes::*` in place
would cut the scope by ~80% but leave a permanent internal inconsistency
contradicting the "break compatibility to keep things clean" principle
captured in CLAUDE.md. The parser surface is ~159 files / ~500
references — all mechanical find-and-replace.

### §1.2 Repo / working directory / memory — full rename

All three external identifiers change in one go:

- **GitHub repo:** `chris-biagini/familyrecipes` → `chris-biagini/mirepoix`
  (via web UI post-merge; GitHub preserves redirects on the old URL)
- **Working directory:** `~/familyrecipes` → `~/mirepoix` (manual `mv`
  post-merge)
- **Claude memory folder:** `~/.claude/projects/-home-claude-familyrecipes`
  → `~/.claude/projects/-home-claude-mirepoix` (manual `mv` post-merge)

**No symlinks.** Defense-in-depth symlinks were considered to cover shell
aliases, tmux sessions, and editor bookmarks that might hardcode the old
path, but the user confirmed nothing local references `~/familyrecipes`
directly (everything resolves through `~` or a project selector). A
clean `mv` is simpler and avoids the long-term path-ambiguity risk of
leaving symlinks in place.

### §1.3 User-facing capitalization — all-lowercase "mirepoix"

Every string a user reads uses the lowercase brand:

- UI: titles, headers, landing page, settings
- Emails: subject lines and body content (`"Sign in to mirepoix"`)
- Documents: README `# mirepoix`, LICENSE file content, help site
- PWA: `name`, `short_name`, `description` in the manifest

Code constants and module names use standard Ruby capitalization
(`Mirepoix`, `Mirepoix::Recipe`). The case convention is:

- **Brand prose / UI string:** lowercase "mirepoix" always, including at
  sentence starts and in headings. Consistent usage is what makes
  lowercase read as intentional rather than as a typo.
- **Code constant:** `Mirepoix` (Ruby module naming convention).
- **Legal / copyright line:** `Copyright (c) 2026 Chris Biagini` — the
  copyright holder is a natural person, not the product.

### §1.4 Copyright holder — Chris Biagini

Copyright attaches to the author. "mirepoix" is a product name, not a
legal entity. Solo-dev standard: `Copyright (c) 2026 Chris Biagini` in
the LICENSE file. This is transferable later via written assignment if
a future LLC is formed to run the hosted service (relevant for Phase 4,
not blocking anything now).

Note: the **O'Saasy license text change itself** is a separate pre-deploy
punch list item (#376). This rebrand only swaps brand references inside
the existing LICENSE file; it does not substitute the O'Saasy text.

### §1.5 Kitchen default title — edit migration 001 in place

`db/migrate/001_create_schema.rb` line 106 currently has
`default: "Family Recipes"` on `kitchens.site_title`. One-line edit:
`default: "mirepoix"`. No new migration, no backfill.

**Why this is the exception to CLAUDE.md's "don't edit shipped
migrations" rule:** the project is still pre-deploy; no production
environment exists; the only live DB is the user's dogfood env, which
will be rebuilt from backups post-rebrand; CI runs migrations from
scratch on every build. The audit trail is captured in this spec and
the implementation plan. A new migration would add ceremony without
value at this stage.

### §1.6 Historical specs and plans — frozen

`docs/superpowers/specs/**` and `docs/superpowers/plans/**` are a
snapshot of design-time reality. A spec written 2026-02-21 references
`FamilyRecipes::Recipe` because that was the class name at the time;
rewriting it to say `Mirepoix::Recipe` is revisionism. Future readers
can use `git log` to find the rebrand commit and the current code as
the source of truth.

The same policy applies to historical memory entries in
`~/.claude/projects/.../memory/*.md` — body text is frozen, only the
top-level `MEMORY.md` index is updated, and a new memory entry is
added post-merge documenting the cutover date.

### §1.7 Help site — update `baseurl` only

The Jekyll help site in `docs/help/` deploys to GitHub Pages at the
repo URL. After the repo rename, its URL becomes
`https://chris-biagini.github.io/mirepoix/`. The `_config.yml` change
is mandatory (`baseurl: "/familyrecipes"` → `"/mirepoix"`); a custom
domain like `help.mirepoix.recipes` is **not** in scope. The help site
is operator documentation, not user-facing production, and a custom
domain is a ~15 minute task that can happen anytime post-merge without
coupling to this PR.

## §2. Code changes

### §2.1 Module and namespace renames

- `module Familyrecipes` in `config/application.rb` → `module Mirepoix`
- `module FamilyRecipes` in `lib/familyrecipes.rb` → `module Mirepoix`
- All ~159 files referencing `FamilyRecipes::*` constants — mechanical
  find-and-replace. Classes affected include (non-exhaustive): `Recipe`,
  `Step`, `Ingredient`, `CrossReference`, `QuickBite`, `Quantity`,
  `UsdaPortionClassifier`, `UsdaClient`, `NutritionCalculator`,
  `RecipeBuilder`, `RecipeSerializer`, `IngredientParser`,
  `LineClassifier`, `SmartTagRegistry`, `ParseError`
- `config.autoload_lib(ignore: %w[assets tasks familyrecipes])` →
  `ignore: %w[assets tasks mirepoix]`. **Load-bearing** — if this
  string doesn't match the new lib directory name, Zeitwerk will try
  to autoload files that use their own require system and explode at
  boot.

### §2.2 Directory renames

- `lib/familyrecipes/` → `lib/mirepoix/` (28 files, directory rename)
- `lib/familyrecipes.rb` → `lib/mirepoix.rb`
- `config/initializers/familyrecipes.rb` → `config/initializers/mirepoix.rb`

### §2.3 User-facing strings

All files containing the literal `"Family Recipes"` get the lowercase
brand. Known locations from the brainstorming scan:

- `app/mailers/magic_link_mailer.rb` (subject)
- `app/views/magic_link_mailer/sign_in_instructions.html.erb`
- `app/views/magic_link_mailer/sign_in_instructions.text.erb`
- `app/views/layouts/application.html.erb`
- `app/views/layouts/auth.html.erb`
- `app/views/landing/show.html.erb`
- PWA manifest view if present
- Any `<title>` tags and page headings

### §2.4 Test code

- `test/ai_import/runner.rb` and related standalone scripts
- Test fixtures that embed the brand name
- Seed recipes in `db/seeds/recipes/` that reference it
- Test expectations for module constants (e.g., assertions on
  `FamilyRecipes::Recipe`)

## §3. Configuration and infrastructure

### §3.1 Package identity

- `package.json`: `"name": "familyrecipes"` → `"name": "mirepoix"`

### §3.2 Build and CI

- `.github/workflows/docker.yml`: local smoke-test image tag
  `familyrecipes:smoke-test` → `mirepoix:smoke-test` (lines 91, 98).
  The GHCR image path uses `${{ github.repository }}` and auto-follows
  the repo rename — no manual change required.
- `Dockerfile`: verify generic (already reported as containing no
  hardcoded app name). No edits expected; implementation plan confirms.
- `.env.example`: brand swap if it contains `APP_NAME=...` or similar.
- `config/debride_allowlist.txt` line 1: references `familyrecipes`,
  update.

### §3.3 Help site

- `docs/help/_config.yml`:
  - `title: familyrecipes help` → `title: mirepoix help`
  - `baseurl: "/familyrecipes"` → `"/mirepoix"`
- `docs/help/_includes/topbar.html`:
  `<span class="topbar-name">familyrecipes</span>` →
  `<span class="topbar-name">mirepoix</span>`
- `docs/help/**/*.md`: brand swap across all content markdown

### §3.4 Database migration

- `db/migrate/001_create_schema.rb` line 106: `default: "Family Recipes"`
  → `default: "mirepoix"` (in-place edit; §1.5 captures the rationale
  for the CLAUDE.md rule exception)

### §3.5 Live project docs

- `README.md`: brand swap throughout
- `CLAUDE.md`: targeted brand swap only — module names, lib paths,
  string references. Stale-reference cleanup (punch list item #3)
  remains a separate task.
- `MEMORY.md` (top-level index at
  `~/.claude/projects/.../memory/MEMORY.md`): live pointers brand-swap.
  Individual historical memory files are frozen per §1.6.
- `LICENSE`: swap any "Family Recipes" references; copyright holder
  remains "Chris Biagini" (§1.4). Do not substitute the O'Saasy text
  itself (separate task #376).

### §3.6 Not modified

- `docs/superpowers/specs/**` and `docs/superpowers/plans/**` —
  frozen per §1.6
- `.git/` directory and commit messages — immutable
- Individual historical memory files — frozen per §1.6
- `app/assets/images/favicon.svg` unless it contains a wordmark
  (implementation verifies; most favicons are shapes/initials)

## §4. Host-side steps (post-merge, manual)

These run after the rebrand PR is squash-merged. They touch state
outside the repo and are not part of the PR diff.

### §4.1 Rename the GitHub repo

Web UI: Settings → rename `familyrecipes` → `mirepoix`. GitHub preserves
redirects on the old URL permanently. The `docker.yml` workflow's
`${{ github.repository }}` auto-updates on the next push, and new GHCR
images publish to `ghcr.io/chris-biagini/mirepoix`.

### §4.2 Update the local git remote

```bash
cd ~/familyrecipes
git remote set-url origin git@github.com:chris-biagini/mirepoix.git
git fetch origin
```

### §4.3 Move the working directory

```bash
cd ~
mv familyrecipes mirepoix
```

### §4.4 Move the Claude memory folder

```bash
cd ~/.claude/projects
mv -- -home-claude-familyrecipes -home-claude-mirepoix
```

The `--` guards against the leading dash being read as a flag.

### §4.5 Verify

Re-open a shell, `cd ~/mirepoix`, and check:

- `git remote -v` shows the new URL
- `bin/rails runner 'puts Rails.application.class.name'` prints
  `Mirepoix::Application`
- `bundle exec rake` passes
- `bin/dev` boots on port 3030
- A new Claude session reads memory from the `-home-claude-mirepoix`
  folder

### §4.6 Cosmetic follow-ups (anytime, not urgent)

- Update the GitHub repo description and topics via the web UI
- Delete old `ghcr.io/chris-biagini/familyrecipes:*` images from GHCR
  once confident nothing's pulling from the old path. GHCR keeps them
  indefinitely otherwise.
- GitHub Pages auto-rebuilds at the new URL after the first push
  following the repo rename.
- Old GHCR image deprecation: at dogfood scale (audience = the user),
  this is theoretical. Mention in README if a wider audience ever
  exists.

## §5. Out of scope

Explicit "not this PR" so the change doesn't drift:

- **O'Saasy license text substitution** — pre-deploy punch list #2 (issue
  #376). This PR only swaps brand references inside the existing LICENSE
  file.
- **CLAUDE.md stale-reference sweep** — punch list #3. This PR only
  renames brand references inside CLAUDE.md.
- **Kamal config (`config/deploy.yml`) adaptation from Fizzy** — no
  deploy config exists yet; belongs to the deploy phase.
- **ActiveRecord encryption key bootstrap** — punch list #8, irreversible
  one-shot ceremony, not a rebrand concern.
- **DNS, TLS, VPS provisioning, Resend setup** — deploy phase.
- **Rewriting historical specs, plans, or memory body text** — §1.6.
- **Custom domain for the help site** (e.g., `help.mirepoix.recipes`) —
  §1.7.
- **Deleting the old `ghcr.io/chris-biagini/familyrecipes:*` GHCR
  images** — cosmetic follow-up, not a rebrand blocker.

## §6. Verification

Runs in CI as part of the PR (not manual):

- `bundle exec rake` — full Rails suite passes (baseline: ~1961 runs /
  6727 assertions at time of spec writing)
- `bundle exec rubocop` — zero offenses
- `bundle exec rake lint:html_safe` — allowlist still matches
- `bundle exec rake security` — Brakeman clean (medium+ confidence)
- `npm test` — JS classifier tests pass
- `npm run build` — esbuild bundles without error

### §6.1 Zero-residue grep

A search across the codebase (excluding frozen historical dirs) must
return empty:

```bash
rg -i '\bfamily[-_ ]?recipes?\b' \
  -- ':!docs/superpowers/specs' ':!docs/superpowers/plans' ':!.git'
```

The implementation plan captures this as a check script (or rake task)
so it runs repeatably and doesn't rot. The regex covers `familyrecipes`,
`family-recipes`, `family_recipes`, `family recipes`, `FamilyRecipes`,
and `Familyrecipes` — all variants in one expression.

### §6.2 Smoke boot

- `bin/dev` starts cleanly
- Landing page at `http://rika:3030/` renders with the new brand
- Mailer preview at `/rails/mailers/magic_link_mailer/sign_in_instructions`
  shows `Subject: Sign in to mirepoix` and lowercase brand in body

## §7. PR strategy

- **One PR, squash-merged.** Rebrands are inherently atomic. Splitting
  creates an unreviewable intermediate state where half the app says
  "mirepoix" and half says "Family Recipes."
- **Branch:** `feature/mirepoix-rebrand`, already created from clean
  `main` (after merging PR #377, the orientation-doc PR).
- **Reviewable as a unit** because most of the diff is mechanical find-
  and-replace; reviewers focus on the few load-bearing changes
  (module declarations, autoload_lib config, migration 001 edit,
  Jekyll baseurl).
- **CI runs on every push** per repo policy; pre-push hook runs lint
  only.

## §8. Rollback plan

- **PR revert via `git revert`** on the squash commit. Low-risk because
  the rebrand is mechanical and doesn't change behavior.
- **Migration 001 edit is not reversible** for any environment that has
  already booted post-rebrand with a fresh DB — but the dogfood env
  rebuilds from backup and CI rebuilds from scratch each build. No
  production environment exists to protect.
- **GitHub repo rename is reversible** via another rename; GitHub
  preserves redirects from all historical names.
- **Host-side steps** (working directory mv, memory folder mv, git
  remote update) are all reversible by running them in reverse.

## §9. Success criteria

One-sentence summary: `rg -i '\bfamily[-_ ]?recipes?\b'` returns only
matches inside `docs/superpowers/specs/` and `docs/superpowers/plans/`
(historical frozen records), and the app boots, serves pages, sends
emails, and passes its full test suite with no brand inconsistencies.

## §10. After this PR

Unblocks the remaining pre-deploy punch list items from the orientation
doc:

2. Apply O'Saasy license (#376)
3. CLAUDE.md stale-reference sweep
4. Update `MEMORY.md` "Passwordless Auth Merged" section (if needed
   after the rebrand)
5. Already complete (annotate 2026-04-08 auth spec as superseded)
6. `rake release:audit` + Playwright pen tests green
7. `rake kitchen:create` smoke test in local Docker build
8. Bootstrap ActiveRecord encryption keys to 1Password + physical backup
9. DNS cut and TLS cert issuance verified

The rebrand earns its own implementation plan via the writing-plans
skill, tracked separately in `docs/superpowers/plans/`.
