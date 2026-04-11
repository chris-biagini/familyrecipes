# Mirepoix Rebrand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the Rails application and domain parser from "Family Recipes" / `FamilyRecipes` / `Familyrecipes` to "mirepoix" / `Mirepoix` across source, config, infrastructure, and live documentation — producing a clean state ready for pre-deploy.

**Architecture:** Mechanical find-and-replace with a `brand:check_residue` rake task as the definitive oracle. Each task is a single commit leaving the app bootable and the test suite passing. The parser module rename (`FamilyRecipes`) and the Rails app module rename (`Familyrecipes`) are independent because their exact-match patterns don't overlap.

**Tech Stack:** Ruby 3.x, Rails 8, Minitest, Zeitwerk (with lib exclusion), Jekyll 4, Docker + GHCR, jsbundling-rails + esbuild.

**Design spec:** `docs/superpowers/specs/2026-04-11-mirepoix-rebrand-design.md` — read §1 before starting for scope commitments.

---

## Conventions for every task

- **Working directory:** `~/familyrecipes` (still, until the host-side steps run post-merge)
- **Branch:** `feature/mirepoix-rebrand` (already created from clean `main` at the spec commit)
- **Ruby find-and-replace tool:** `sed -i` (GNU sed on Linux, in-place). When a pattern has risk of false positives, use `perl -pi -e` with word boundaries.
- **File discovery:** `rg -l PATTERN` (respects `.gitignore` by default, so `.git/`, `node_modules/`, `tmp/`, `log/`, `storage/`, `public/assets/`, `_site/`, `.jekyll-cache/` are all auto-excluded). Explicit excludes for frozen historical dirs via `--glob '!docs/superpowers/specs/**' --glob '!docs/superpowers/plans/**'`.
- **Test suite baseline:** `bundle exec rake test` — ~1961 runs / 6727 assertions at spec time.
- **Verification between tasks:** `bundle exec rake` (runs lint + test) + `bundle exec rake brand:check_residue`.
- **Commit style:** conventional subject ("Rebrand: …"), body explains the "why" if non-obvious, Co-Authored-By line per CLAUDE.md.

## File structure

Files created:
- `lib/tasks/brand.rake` — residue-check rake task (Task 1)
- `docs/superpowers/plans/2026-04-11-mirepoix-rebrand.md` — this file (created during planning, no task touches it)

Files renamed (`git mv`, with content edits):
- `lib/familyrecipes/` → `lib/mirepoix/` (directory with 28 files)
- `lib/familyrecipes.rb` → `lib/mirepoix.rb`
- `config/initializers/familyrecipes.rb` → `config/initializers/mirepoix.rb`
- `test/lib/familyrecipes/` → `test/lib/mirepoix/` (parallel test directory)
- `test/familyrecipes_test.rb` → `test/mirepoix_test.rb` (top-level parser test file)
- `lib/tasks/familyrecipes.rake` → `lib/tasks/mirepoix.rake` (rake task file holding the `default` target; renamed in Task 6)

Files edited (content-only):
- `config/application.rb` — module name, autoload_lib ignore list, comment
- `db/migrate/001_create_schema.rb` — kitchen title default (line 106)
- `package.json` — name field
- `.github/workflows/docker.yml` — local smoke-test image tag
- `.env.example` — brand references (if any)
- `config/debride_allowlist.txt` — brand references
- `docs/help/_config.yml` — title + baseurl
- `docs/help/_includes/topbar.html` — topbar name
- `docs/help/**/*.md` — content brand swap
- `README.md` — brand swap
- `CLAUDE.md` — brand swap (module names, lib paths, "Two namespaces" paragraph)
- `LICENSE` — brand swap in any "Family Recipes" references (not the license text itself)
- All files matching `rg 'FamilyRecipes'` outside frozen dirs (Task 2 sweep)
- All files matching `rg 'Familyrecipes'` outside frozen dirs (Task 3 sweep)
- All files matching `rg 'familyrecipes'` outside frozen dirs (Task 6 sweep)
- All files matching `rg 'Family Recipes'` outside frozen dirs (Task 4 sweep)

Plus `~/.claude/projects/-home-claude-familyrecipes/memory/MEMORY.md` (live index file; Task 8 touches it but it's outside the repo — see that task).

---

## Task 1: Add brand-residue check rake task

**Files:**
- Create: `lib/tasks/brand.rake`
- Test: `bundle exec rake brand:check_residue` run before and after

This task creates the definitive oracle for the rebrand. The rake task uses `rg` to find any residue of the old brand (case-insensitive, all variants in one expression) outside the frozen historical directories, and exits non-zero if anything is found. Running it at the start will report massive residue; running it at the end must report none.

- [ ] **Step 1: Create the rake task file**

Create `lib/tasks/brand.rake` with this exact content:

```ruby
# frozen_string_literal: true

# Brand-residue check for the 2026-04-11 Mirepoix rebrand. Fails if any variant
# of the old "Family Recipes" brand is found in tracked files outside the
# frozen historical directories. Runs in CI (and manually) to prevent
# accidental reintroduction of old brand strings.
#
# Deliberately does NOT depend on :environment — the check is a pure string
# scan via `rg` and must keep working even if Rails boot is temporarily
# broken mid-rebrand. Rails/RakeEnvironment is disabled for that reason.
namespace :brand do # rubocop:disable Metrics/BlockLength
  desc 'Fail if any "Family Recipes" brand residue remains in tracked files'
  task :check_residue do # rubocop:disable Rails/RakeEnvironment
    require 'open3'

    pattern = '\bfamily[-_ ]?recipes?\b'
    excludes = %w[
      docs/superpowers/specs/**
      docs/superpowers/plans/**
      .git/**
    ]
    cmd = ['rg', '-i', '-c', '--no-heading', pattern]
    excludes.each { |glob| cmd.push('--glob', "!#{glob}") }
    cmd.push('.')

    output, status = Open3.capture2e(*cmd)

    case status.exitstatus
    when 0
      total = output.lines.sum { |line| line.split(':').last.to_i }
      puts "Brand residue found (#{total} matches across #{output.lines.size} files):"
      puts output
      abort
    when 1
      puts "Clean: no 'Family Recipes' brand residue detected."
    else
      puts "rg error (exit #{status.exitstatus}):"
      puts output
      abort
    end
  end
end
```

**Why `cmd.push('.')` matters:** `rg` invoked via `Open3.capture2e` runs with stdin connected to an empty pipe (not a tty). Without an explicit path argument, `rg` reads from stdin, finds no input, and exits 1 — which the rake task would interpret as "Clean: no residue" regardless of actual state. The explicit `.` argument tells `rg` to recursively search the current directory.

**Why the cop disables:** `Metrics/BlockLength` fires at 27 lines (limit is 25) — matching how `kitchen.rake` and `release_audit.rake` handle the same cop. `Rails/RakeEnvironment` wants `:environment` as a prerequisite, but the oracle must stay independent of Rails boot so it can run when the app is temporarily broken mid-rebrand (e.g., after a module rename but before dependent files are updated). Adding `:environment` would couple the oracle to Rails boot success and add startup cost with no benefit.

**Ripgrep dependency:** the rake task shells out to `rg`. Ripgrep must be installed on the machine running the task (dev laptop, CI image, etc.). If `rg` is missing, `Open3.capture2e` raises `ENOENT`. CI currently assumes `rg` is available — if the Docker build image doesn't include it, add it in Task 9's final verification.

- [ ] **Step 2: Run the task to capture the starting residue count**

```bash
cd ~/familyrecipes
bundle exec rake brand:check_residue
```

Expected: **FAILS** with a large list of files (hundreds of matches). Note the total count in the terminal output — this is your "before" baseline. Copy it into the commit message so future history shows the starting point.

- [ ] **Step 3: Wire the check into the default rake task**

The default task is NOT in the top-level `Rakefile` (that file only contains `Rails.application.load_tasks`). It lives in `lib/tasks/familyrecipes.rake`. Find the existing line:

```bash
rg -n 'task default' lib/tasks/familyrecipes.rake
```

Expected output: something like `task default: %i[lint test]` inside a `begin/rescue LoadError` block (the rescue branch falls back to `:test` only when RuboCop isn't available).

Edit the `task default: %i[lint test]` line to include `brand:check_residue`:

```ruby
task default: %i[lint test brand:check_residue]
```

Leave the `rescue LoadError` fallback (`task default: :test`) as-is — it only runs in the rare case RuboCop isn't loadable, and the residue check doesn't depend on RuboCop anyway.

**Note:** the default task will now fail until the rebrand is complete. That's intentional — the whole point is that the oracle fails until the work is done. During this PR, verification uses `bundle exec rake test` (bypass default) until the final task, which switches back to `bundle exec rake`.

**Task 6 will rename this file** from `lib/tasks/familyrecipes.rake` to `lib/tasks/mirepoix.rake` as part of the config/CI identifier sweep. The contents don't change then — only the filename. The line you're editing now lives in the same logical file regardless of name.

- [ ] **Step 4: Verify `bundle exec rake test` still runs the test suite directly**

```bash
bundle exec rake test
```

Expected: full test suite passes (~1961 runs, 6727 assertions). No failures. This command is how we verify tests at every checkpoint — NOT `bundle exec rake` (which now fails due to residue).

- [ ] **Step 5: Commit**

```bash
git add lib/tasks/brand.rake lib/tasks/familyrecipes.rake
git commit -m "$(cat <<'EOF'
Rebrand: brand:check_residue oracle

Introduces a rake task that fails if any "Family Recipes" brand variant
remains in tracked files outside the frozen historical directories
(docs/superpowers/specs, docs/superpowers/plans, .git). Wired into the
default rake task so CI will fail until the rebrand completes.

Verification during the rebrand PR uses `bundle exec rake test` directly
(which bypasses the failing default) until the final task, which
switches back to `bundle exec rake`.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Rename parser module (`FamilyRecipes` → `Mirepoix`)

**Files:**
- Rename: `lib/familyrecipes/` → `lib/mirepoix/` (directory, 28 files)
- Rename: `lib/familyrecipes.rb` → `lib/mirepoix.rb`
- Rename: `config/initializers/familyrecipes.rb` → `config/initializers/mirepoix.rb`
- Rename: `test/lib/familyrecipes/` → `test/lib/mirepoix/` (parallel test directory)
- Rename: `test/familyrecipes_test.rb` → `test/mirepoix_test.rb` (top-level parser test)
- Modify: `config/application.rb` — autoload_lib ignore list + comment
- Modify: all files matching `rg 'FamilyRecipes'` outside frozen dirs (module declarations + `FamilyRecipes::` references)

This is the largest and most structurally load-bearing task. It must be one atomic commit because intermediate states don't boot: the `require_relative` paths in the module entry point, the directory name, the autoload_lib ignore list, and every `FamilyRecipes::` reference all need to move together or Zeitwerk will either try to autoload files that use their own require system (explosion at boot) or fail to find constants the app code depends on.

The test files/dirs rename together because Ruby convention pairs `test/foo_test.rb` with `lib/foo.rb` and `test/lib/foo/` with `lib/foo/`, and Minitest discovers tests by glob `test/**/*_test.rb` — the filename doesn't need to match the class name for discovery, but matching-names is a hard codebase convention worth preserving.

- [ ] **Step 1: Move the directory and module entry point files**

```bash
cd ~/familyrecipes
git mv lib/familyrecipes lib/mirepoix
git mv lib/familyrecipes.rb lib/mirepoix.rb
git mv config/initializers/familyrecipes.rb config/initializers/mirepoix.rb
git mv test/lib/familyrecipes test/lib/mirepoix
git mv test/familyrecipes_test.rb test/mirepoix_test.rb
```

Verify with `git status` — you should see five rename entries. No content changes yet.

- [ ] **Step 2: Update `lib/mirepoix.rb` — module name, require paths, header comment**

Read `lib/mirepoix.rb` to see the current content. Then edit it with the following changes:

1. **Replace the header comment (lines 8-13).** The current comment explains the two-namespace distinction which no longer exists. Replace the six-line comment block ending at `module FamilyRecipes` with:

```ruby
# Root module for the recipe parser pipeline — a pure-Ruby domain layer that
# knows nothing about Rails. Parses Markdown recipe files into structured value
# objects (Recipe, Step, Ingredient, CrossReference, QuickBite) and computes
# nutrition data. Loaded once at boot via config/initializers/mirepoix.rb, not
# through Zeitwerk (see config/application.rb autoload_lib ignore list).
module Mirepoix
```

2. **Change every `require_relative 'familyrecipes/...'` to `require_relative 'mirepoix/...'`.** There are ~24 lines at the bottom of the file (check by scrolling). Use Edit with `replace_all: true`:

- old_string: `require_relative 'familyrecipes/`
- new_string: `require_relative 'mirepoix/`
- replace_all: true

- [ ] **Step 3: Update `config/initializers/mirepoix.rb` — comment and require path**

Read the file. It should be a short three-line file (comment + require). Edit to:

```ruby
# frozen_string_literal: true

# Loads the Mirepoix domain/parser module at boot time. These classes live
# outside app/ and are not autoloaded by Zeitwerk — they're loaded once here and
# remain in memory. Changes to lib/mirepoix/ require a server restart.
require_relative '../../lib/mirepoix'
```

- [ ] **Step 4: Update `config/application.rb` — autoload_lib ignore list and comment**

Read the file. Find the block:

```ruby
    # Don't autoload lib/familyrecipes — it uses its own require system
    config.autoload_lib(ignore: %w[assets tasks familyrecipes])
```

Edit to:

```ruby
    # Don't autoload lib/mirepoix — it uses its own require system
    config.autoload_lib(ignore: %w[assets tasks mirepoix])
```

**Do NOT touch `module Familyrecipes` on line 16 yet** — that's Task 3 (different pattern, separate commit).

- [ ] **Step 5: Global find-and-replace `FamilyRecipes` → `Mirepoix`**

```bash
rg -l 'FamilyRecipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**' \
  | xargs sed -i 's/FamilyRecipes/Mirepoix/g'
```

Note: `FamilyRecipes` (uppercase R) is the exact pattern — `Familyrecipes` (lowercase r) is a different string that sed won't match. They're independent.

- [ ] **Step 6: Verify the parser module loads**

```bash
bundle exec rails runner 'puts Mirepoix::CONFIG.inspect'
```

Expected output: `{:quick_bites_filename=>"Quick Bites.md", :quick_bites_category=>"Quick Bites"}` (or similar — the point is that `Mirepoix::CONFIG` resolves).

If this fails with `NameError: uninitialized constant Mirepoix::CONFIG`, something didn't rename cleanly. Common causes:
- A `require_relative` line in `lib/mirepoix.rb` still has `familyrecipes/` (grep it)
- The `autoload_lib` ignore list still has `familyrecipes` (grep `config/application.rb`)
- The initializer still says `lib/familyrecipes`

Fix and retry.

- [ ] **Step 7: Run the full test suite**

```bash
bundle exec rake test
```

Expected: all tests pass. If failures appear, the root cause is almost always a missed `FamilyRecipes::` reference. Find stragglers:

```bash
rg 'FamilyRecipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**'
```

Expected: empty output. If non-empty, re-run step 5 (sed) against the missed files or Edit them individually.

- [ ] **Step 8: Run rubocop**

```bash
bundle exec rubocop
```

Expected: 0 offenses. The rename is purely textual and shouldn't introduce style issues, but verify.

- [ ] **Step 9: Residue check (partial)**

```bash
bundle exec rake brand:check_residue
```

Expected: still FAILS (lots of residue remaining — `Family Recipes` strings, `Familyrecipes` module, `familyrecipes` in config). Note the count has dropped from the Task 1 baseline; you're making progress.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Rebrand: parser module FamilyRecipes -> Mirepoix

Rename lib/familyrecipes/ -> lib/mirepoix/ (28 files, directory rename).
Rename lib/familyrecipes.rb -> lib/mirepoix.rb and update require_relative
paths for all 24 sub-files. Rename config/initializers/familyrecipes.rb
-> config/initializers/mirepoix.rb and update its require path. Update
config/application.rb autoload_lib ignore list from familyrecipes to
mirepoix. Global find-and-replace FamilyRecipes -> Mirepoix across all
tracked files outside docs/superpowers/specs and docs/superpowers/plans.

Test suite passes. Rails app module (Familyrecipes, lowercase r) remains
separate; renamed in the next commit.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Rename Rails app module (`Familyrecipes` → `Mirepoix`)

**Files:**
- Modify: `config/application.rb` line 16 (module declaration)
- Modify: any other files with `Familyrecipes` (lowercase r) outside frozen dirs

Task 2 renamed `FamilyRecipes` (uppercase R, parser). This task renames `Familyrecipes` (lowercase r, Rails app). They're different exact-match strings, so the previous sed didn't touch this. After this task, both forms are gone and `Mirepoix` is the sole module name.

- [ ] **Step 1: Find all current references**

```bash
rg 'Familyrecipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**'
```

Expected results: only 2 active files should match — `config/application.rb:16` and `CLAUDE.md` (the "Two namespaces" paragraph). Historical docs in `docs/superpowers/plans/2026-02-21-rails-migration-plan.md` are excluded by the glob.

If additional files appear, include them in Step 2.

- [ ] **Step 2: Global find-and-replace `Familyrecipes` → `Mirepoix`**

```bash
rg -l 'Familyrecipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**' \
  | xargs sed -i 's/Familyrecipes/Mirepoix/g'
```

- [ ] **Step 3: Verify the Rails app module loads**

```bash
bundle exec rails runner 'puts Rails.application.class.name'
```

Expected output: `Mirepoix::Application`

If this fails with `NameError` or similar, there's a straggler. Re-run the grep from Step 1 and fix any remaining files.

- [ ] **Step 4: Run the full test suite**

```bash
bundle exec rake test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Rebrand: Rails app module Familyrecipes -> Mirepoix

Rename module Familyrecipes in config/application.rb to module Mirepoix,
plus any CLAUDE.md references. With Task 2 (FamilyRecipes -> Mirepoix),
both namespaces now collapse to a single Mirepoix module — the one-word
brand eliminates the pre-rebrand case-parallel distinction entirely.

Rails.application.class.name now returns "Mirepoix::Application".

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: User-facing strings ("Family Recipes" → "mirepoix")

**Files:**
- Modify: all files matching `rg 'Family Recipes'` outside frozen dirs
- Notable: `app/mailers/magic_link_mailer.rb`, `app/views/magic_link_mailer/*`, `app/views/layouts/application.html.erb`, `app/views/layouts/auth.html.erb`, `app/views/landing/show.html.erb`, PWA manifest if present, any `<title>` tags and `<h1>` headings
- Explicitly EXCLUDED from this task: `db/migrate/001_create_schema.rb` (Task 5 handles this separately per spec §1.5)

Per spec §1.3, the user-facing brand is lowercase "mirepoix". This task replaces the literal two-word "Family Recipes" with lowercase single-word "mirepoix" everywhere a user would read it.

- [ ] **Step 1: Find all current references**

```bash
rg 'Family Recipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**' \
  --glob '!db/migrate/001_create_schema.rb'
```

Expected: approximately 40 files. Scan the output quickly — any files that look like historical release notes or changelog entries should also be excluded (in which case add them to the `--glob '!...'` list). For README.md, CLAUDE.md, and live source, proceed.

- [ ] **Step 2: Global find-and-replace**

```bash
rg -l 'Family Recipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**' \
  --glob '!db/migrate/001_create_schema.rb' \
  | xargs sed -i 's/Family Recipes/mirepoix/g'
```

- [ ] **Step 3: Verify mailer subject**

```bash
rg -n 'Sign in to' app/mailers/magic_link_mailer.rb
```

Expected: `Sign in to mirepoix` (lowercase). Not `Sign in to Mirepoix`.

- [ ] **Step 4: Verify layout title**

```bash
rg -n '<title>' app/views/layouts/
```

Expected: any `<title>` tags use lowercase `mirepoix`.

- [ ] **Step 5: Find and fix test expectations**

Some tests may assert against the old string. Re-run the test suite and see what breaks:

```bash
bundle exec rake test 2>&1 | head -80
```

If any tests fail because they expect `"Family Recipes"`, update those test assertions to expect `"mirepoix"`. The failures will look like:

```
FAIL ...
Expected: "Family Recipes"
  Actual: "mirepoix"
```

Edit each failing test's expected value to `"mirepoix"`. Re-run tests until green.

- [ ] **Step 6: Residue check (partial)**

```bash
bundle exec rake brand:check_residue
```

Expected: still FAILS (Task 5 + 6 + 7 + 8 remain), but the count continues to drop.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Rebrand: user-facing strings "Family Recipes" -> "mirepoix"

Sweep app/, test/, lib/, config/, and live docs replacing the literal
"Family Recipes" with lowercase "mirepoix" per the spec §1.3 convention.
Migration 001 handled separately in the next commit.

Updates affected test assertions that check for the old string literal.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Migration 001 default title (in-place edit)

**Files:**
- Modify: `db/migrate/001_create_schema.rb` line 106

This is the one CLAUDE.md rule exception documented in spec §1.5: editing a shipped migration in place. Justified because the project is pre-deploy (no production DB to protect) and the user's dogfood env rebuilds from backup.

- [ ] **Step 1: Confirm the line to edit**

```bash
rg -n '"Family Recipes"' db/migrate/001_create_schema.rb
```

Expected: one match, likely on line 106 or nearby, showing `default: "Family Recipes"`. If the line number has shifted due to prior commits, use whatever `rg` reports.

- [ ] **Step 2: Edit the line**

Use Edit to change `default: "Family Recipes"` to `default: "mirepoix"` in `db/migrate/001_create_schema.rb`. The `old_string` should include enough context to be unique — for example the whole column definition line.

- [ ] **Step 3: Verify migration runs from scratch**

```bash
bundle exec rails db:drop db:create db:migrate db:seed
```

Expected: clean migration, no errors. Verifies the in-place edit is syntactically valid and CI-safe.

- [ ] **Step 4: Run the full test suite**

```bash
bundle exec rake test
```

Expected: all tests pass. If any tests seed a kitchen and then check `site_title == "Family Recipes"`, they should have been caught in Task 4's sweep; if not, fix them now.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/001_create_schema.rb
git commit -m "$(cat <<'EOF'
Rebrand: kitchen default title in migration 001

Edit db/migrate/001_create_schema.rb in place, changing the kitchens
site_title column default from "Family Recipes" to "mirepoix".

This is the single CLAUDE.md rule exception documented in the rebrand
design spec (§1.5). Justified because the project is pre-deploy — no
production DB exists to protect, the dogfood env rebuilds from backup,
and CI runs migrations from scratch on every build. The audit trail
lives in the spec.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Config, CI, and packaging (`familyrecipes` lowercase)

**Files:**
- Rename: `lib/tasks/familyrecipes.rake` → `lib/tasks/mirepoix.rake` (the rake task file holding the default target, modified during Task 1 but not renamed)
- Modify: `package.json` (name field)
- Modify: `.github/workflows/docker.yml` (smoke-test image tag)
- Modify: `.env.example` (if contains brand references)
- Modify: `config/debride_allowlist.txt` (brand references)
- Modify: any other files with lowercase `familyrecipes` outside frozen dirs, the `lib/mirepoix/` directory (already renamed), and `docs/help/` (Task 7 handles help site separately)

Lowercase `familyrecipes` is the DNS-safe / URL-safe form. It appears in package identifiers, Docker tags, filenames for supporting rake tasks, and any file that references the old working-directory name or repo name as a bare word.

- [ ] **Step 1: Rename the rake task file**

```bash
git mv lib/tasks/familyrecipes.rake lib/tasks/mirepoix.rake
```

This file holds the top-level `:test`, `:lint`, and `default` task definitions. The filename contains the bare word `familyrecipes` which the content-sweep in Step 3 won't fix. Its contents (after Task 1's edit) already reference `brand:check_residue` in the default task list — no content change needed here.

- [ ] **Step 2: Find all lowercase `familyrecipes` residue**

```bash
rg 'familyrecipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**' \
  --glob '!docs/help/**'
```

Expected output includes `package.json`, `.github/workflows/docker.yml`, `config/debride_allowlist.txt`, possibly `.env.example`, and possibly a few test files or other configs. The `docs/help/` glob is excluded because Task 7 handles it separately (help site also has structural changes like baseurl). Historical specs and plans are always excluded.

- [ ] **Step 3: Global find-and-replace**

```bash
rg -l 'familyrecipes' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**' \
  --glob '!docs/help/**' \
  | xargs sed -i 's/familyrecipes/mirepoix/g'
```

- [ ] **Step 4: Verify `package.json`**

```bash
rg -n '"name"' package.json
```

Expected: `"name": "mirepoix"`.

- [ ] **Step 5: Verify `.github/workflows/docker.yml` smoke-test tag**

```bash
rg -n 'mirepoix:smoke-test' .github/workflows/docker.yml
```

Expected: at least two matches (originally lines 91 and 98). The `${{ github.repository }}` reference for the GHCR image path remains unchanged — it auto-follows the post-merge repo rename.

- [ ] **Step 6: Verify the renamed rake task file still works**

```bash
bundle exec rake -T | head -20
```

Expected: the rake task list still shows `test`, `lint`, `brand:check_residue` etc. If rake can't load the tasks at all, the rename broke something — check for `require` statements that reference the old filename.

- [ ] **Step 7: Run the test suite**

```bash
bundle exec rake test
```

Expected: tests still pass. This task shouldn't touch any application behavior, only config text.

- [ ] **Step 8: Verify `npm run build` still works**

```bash
npm run build
```

Expected: esbuild bundles without error. The `package.json` name change doesn't affect build tooling.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Rebrand: config and CI identifiers familyrecipes -> mirepoix

Rename lib/tasks/familyrecipes.rake -> lib/tasks/mirepoix.rake, update
package.json name, the .github/workflows/docker.yml local smoke-test
image tag, config/debride_allowlist.txt, .env.example, and any other
files referencing the lowercase bare-word identifier.

The GHCR image path uses \${{ github.repository }} and auto-follows the
post-merge GitHub repo rename — no manual change needed.

Help site (docs/help/) handled separately in the next commit to keep
the Jekyll baseurl change isolated.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Jekyll help site (`docs/help/`)

**Files:**
- Modify: `docs/help/_config.yml` — title and baseurl
- Modify: `docs/help/_includes/topbar.html` — topbar name span
- Modify: `docs/help/**/*.md` — content brand swap

The help site is a Jekyll site deployed to GitHub Pages. Per spec §1.7, the `baseurl` change is mandatory (internal links break otherwise) and no custom domain is in scope for this PR.

- [ ] **Step 1: Update `_config.yml`**

Read `docs/help/_config.yml`. It should have at least two lines to edit:

```yaml
title: familyrecipes help
...
baseurl: "/familyrecipes"
```

Edit to:

```yaml
title: mirepoix help
...
baseurl: "/mirepoix"
```

- [ ] **Step 2: Update `_includes/topbar.html`**

Read `docs/help/_includes/topbar.html`. Find the line:

```html
<span class="topbar-name">familyrecipes</span>
```

Edit to:

```html
<span class="topbar-name">mirepoix</span>
```

- [ ] **Step 3: Sweep content markdown for "Family Recipes"**

```bash
rg -l 'Family Recipes' docs/help/ | xargs sed -i 's/Family Recipes/mirepoix/g'
```

- [ ] **Step 4: Sweep content markdown for lowercase `familyrecipes`**

```bash
rg -l 'familyrecipes' docs/help/ | xargs sed -i 's/familyrecipes/mirepoix/g'
```

This catches URL-path references, install instructions, and any remaining bare-word appearances.

- [ ] **Step 5: Verify residue in `docs/help/` is clean**

```bash
rg -i '\bfamily[-_ ]?recipes?\b' docs/help/
```

Expected: empty output. If any stragglers appear, fix them with Edit.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Rebrand: Jekyll help site docs/help/

Update _config.yml title and baseurl, _includes/topbar.html topbar
name, and sweep all content markdown for "Family Recipes" and
"familyrecipes" residue.

Post-merge, the help site will live at
https://chris-biagini.github.io/mirepoix/ once the GitHub repo rename
and Pages rebuild complete. Custom domain for the help site is out of
scope for this PR (spec §1.7).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Live project docs — README, CLAUDE.md, LICENSE, MEMORY.md index

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md` — including the "Two namespaces" paragraph rewrite (no longer relevant after the rebrand)
- Modify: `LICENSE` — brand references only, NOT the license text itself
- Modify: `~/.claude/projects/-home-claude-familyrecipes/memory/MEMORY.md` — index-level brand swap only

This task is the cleanup of live documentation that describes the project itself. Historical specs and plans remain frozen per spec §1.6. Individual historical memory files remain frozen per §1.6; only the index file `MEMORY.md` is touched.

**Important:** this task touches a file outside the repo (`~/.claude/projects/.../memory/MEMORY.md`). That edit doesn't get committed to the repo — it's a live state edit. The commit in this task covers only the in-repo files (README, CLAUDE.md, LICENSE).

- [ ] **Step 1: Sweep README.md**

```bash
sed -i 's/Family Recipes/mirepoix/g; s/FamilyRecipes/Mirepoix/g; s/Familyrecipes/Mirepoix/g; s/familyrecipes/mirepoix/g' README.md
```

Read the result to confirm it's coherent — README often has install instructions, Docker commands, etc. that may need manual cleanup if the bulk substitution left an awkward phrase. For instance, "clone familyrecipes" becomes "clone mirepoix" which is fine, but "the familyrecipes/familyrecipes Docker image" might need more care. Fix any awkward phrasings with Edit.

- [ ] **Step 2: Sweep CLAUDE.md — brand references only**

```bash
sed -i 's/Family Recipes/mirepoix/g; s/FamilyRecipes/Mirepoix/g; s/Familyrecipes/Mirepoix/g; s/familyrecipes/mirepoix/g; s/lib\/familyrecipes/lib\/mirepoix/g' CLAUDE.md
```

- [ ] **Step 3: Rewrite the "Two namespaces" paragraph in CLAUDE.md**

The paragraph under "## Architecture" that currently begins "**Two namespaces.**" exists only to explain the pre-rebrand case-parallel quirk which no longer exists. After the bulk sed, it will read something like:

> **Two namespaces.** Rails app module: `Mirepoix` (lowercase r). Domain parser module: `Mirepoix` (uppercase R). Different constants, no collision.

which is contradictory. Replace the entire paragraph (from `**Two namespaces.**` through the end of that paragraph) with a simpler statement:

```markdown
**Module.** `Mirepoix` is reopened in two places: `config/application.rb`
declares `Mirepoix::Application` (the Rails app), and `lib/mirepoix.rb`
declares the parser classes (`Mirepoix::Recipe`, `Mirepoix::Step`,
`Mirepoix::Ingredient`, etc.). The parser pipeline is:
`LineClassifier` → `RecipeBuilder` → `Mirepoix::Recipe`;
`MarkdownImporter` is the sole write-path entry point.
```

The exact surrounding context (the rest of the architecture section) is unchanged. Use Edit with a precise `old_string` spanning the full existing paragraph so the replacement lands exactly.

- [ ] **Step 4: Sweep LICENSE for brand references**

Read `LICENSE`. If it contains "Family Recipes" or "FamilyRecipes" or similar, replace with `mirepoix`. The copyright holder line should remain `Copyright (c) 2026 Chris Biagini` per spec §1.4 (do NOT change the copyright holder).

**Do not** substitute the license text itself — that's a separate task (#376). Only brand references.

- [ ] **Step 5: Update MEMORY.md index (outside the repo, not committed)**

```bash
sed -i 's/Family Recipes/mirepoix/g; s/FamilyRecipes/Mirepoix/g; s/Familyrecipes/Mirepoix/g; s/familyrecipes/mirepoix/g' \
  ~/.claude/projects/-home-claude-familyrecipes/memory/MEMORY.md
```

After editing, read the file and spot-check — the index entries should still be coherent one-liners. Individual memory files (the detail documents linked from the index) remain frozen per spec §1.6.

Note: this edit touches a file OUTSIDE the git repo and is not committed. It's a live state update to the memory system. The in-repo commit in Step 7 does not include this file.

- [ ] **Step 6: Run the full test suite**

```bash
bundle exec rake test
```

Expected: tests pass. Docs changes don't affect code but the test suite run is the standard checkpoint.

- [ ] **Step 7: Commit (repo files only)**

```bash
git add README.md CLAUDE.md LICENSE
git commit -m "$(cat <<'EOF'
Rebrand: live project docs

Update README.md, CLAUDE.md, and LICENSE with brand-swap references:
"Family Recipes" -> "mirepoix" (user-facing), FamilyRecipes/Familyrecipes
-> Mirepoix (code constants), familyrecipes -> mirepoix (lowercase
identifier), lib/familyrecipes -> lib/mirepoix (path).

CLAUDE.md's "Two namespaces" paragraph is rewritten to reflect the
post-rebrand reality (single Mirepoix module reopened in two places).
Stale-reference sweep for other CLAUDE.md content (trusted-header
leftovers, old phase descriptions) remains a separate task per the
orientation doc punch list.

LICENSE copyright holder remains "Chris Biagini" (spec §1.4). License
text itself is out of scope — the O'Saasy substitution is task #376.

Memory index (~/.claude/projects/.../memory/MEMORY.md) also updated
but not part of this commit (lives outside the repo).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Final verification and PR

**Files:** none modified; verification only

This task confirms the rebrand is complete and opens the PR. The residue check should now pass, the default rake task should pass (no more failing brand oracle), and the boot smoke test should show the new brand end-to-end.

- [ ] **Step 1: Zero-residue check**

```bash
bundle exec rake brand:check_residue
```

Expected: **PASSES** with `Clean: no 'Family Recipes' brand residue detected.` If this fails, the report will show exactly which files still have residue. Fix them with Edit or another targeted sed run and re-check.

- [ ] **Step 2: Manual content grep cross-check (belt and suspenders)**

```bash
rg -i '\bfamily[-_ ]?recipes?\b' \
  --glob '!docs/superpowers/specs/**' \
  --glob '!docs/superpowers/plans/**'
```

Expected: empty output. If the rake task passed but this grep finds something, there's a glob escaping mismatch in the rake task — fix it.

- [ ] **Step 3: Filename residue check**

The `brand:check_residue` rake task scans file *contents*, not filenames. Run this `find` command to verify no residual filenames remain:

```bash
find . -type f -iname '*family*recipe*' \
  -not -path './.git/*' \
  -not -path './docs/superpowers/specs/*' \
  -not -path './docs/superpowers/plans/*' \
  -not -path './tmp/*' \
  -not -path './log/*' \
  -not -path './storage/*' \
  -not -path './node_modules/*' \
  -not -path './_site/*' \
  -not -path './public/assets/*' \
  -not -path './.jekyll-cache/*'
```

Then directories:

```bash
find . -type d -iname '*family*recipe*' \
  -not -path './.git/*' \
  -not -path './docs/superpowers/specs/*' \
  -not -path './docs/superpowers/plans/*'
```

Expected: both commands return empty output. At the start of the rebrand, the filesystem contained these residual names (known set): `lib/familyrecipes/`, `lib/familyrecipes.rb`, `config/initializers/familyrecipes.rb`, `test/lib/familyrecipes/`, `test/familyrecipes_test.rb`, and `lib/tasks/familyrecipes.rake`. All should have been renamed by Tasks 2 (first five) and 6 (rake task file). If any remain, use `git mv` to fix them, re-run tests and the content check, and include the fix in a new commit.

- [ ] **Step 4: Full default rake (lint + test + residue)**

```bash
bundle exec rake
```

Expected: PASSES — RuboCop clean, full test suite green, residue check clean. This is the signal that the rebrand is complete.

- [ ] **Step 5: Security audit**

```bash
bundle exec rake security
```

Expected: Brakeman clean (medium+ confidence). The rebrand is textual and shouldn't introduce security issues, but verify.

- [ ] **Step 6: JS build**

```bash
npm run build && npm test
```

Expected: esbuild bundles without error, JS classifier tests pass.

- [ ] **Step 7: Boot smoke test**

In a separate terminal:

```bash
cd ~/familyrecipes
bin/dev
```

Wait for "Listening on 0.0.0.0:3030" in the log. Then in another terminal:

```bash
curl -s http://rika:3030/ | grep -i -E '<title|mirepoix|family'
```

Expected: `<title>` contains `mirepoix` (lowercase), no occurrence of `family` or `Family Recipes`.

Stop the dev server (Ctrl-C in its terminal) when done.

- [ ] **Step 8: Mailer preview**

With the dev server running, list available mailer previews:

```bash
curl -s http://rika:3030/rails/mailers | grep -i magic_link
```

Find the exact preview URL from the output (something like `/rails/mailers/magic_link_mailer/<preview_method>`), then:

```bash
curl -s http://rika:3030<path_from_above> | grep -i -E 'mirepoix|family'
```

Expected: body contains lowercase `mirepoix`, no `Family Recipes`. Also confirm the subject line — either by reading the preview's HTML frame or by reading `app/mailers/magic_link_mailer.rb` and verifying the `subject:` value is `"Sign in to mirepoix"`.

- [ ] **Step 9: Rails console sanity check**

```bash
bundle exec rails runner 'puts Rails.application.class.name, Mirepoix::CONFIG[:quick_bites_filename]'
```

Expected output:

```
Mirepoix::Application
Quick Bites.md
```

Confirms both the Rails app module and the parser module resolve under the new name.

- [ ] **Step 10: Push the branch**

```bash
git push origin feature/mirepoix-rebrand
```

(Branch already has `-u origin/feature/mirepoix-rebrand` set from the design-spec commit, so `git push` is sufficient.)

- [ ] **Step 11: Open the PR**

```bash
gh pr create --title "Rebrand: Family Recipes -> mirepoix" --body "$(cat <<'EOF'
## Summary

Mechanical rename of the Rails application and domain parser from "Family Recipes" / \`FamilyRecipes\` / \`Familyrecipes\` to "mirepoix" / \`Mirepoix\` across source, config, infrastructure, and live documentation. Pre-deploy punch list item #1 from the orientation doc.

Design spec: \`docs/superpowers/specs/2026-04-11-mirepoix-rebrand-design.md\`.

**Scope commitments (see spec §1 for details):**

- Full internal namespace rename (both \`FamilyRecipes::*\` parser and \`Familyrecipes::Application\` Rails app collapse to \`Mirepoix\`)
- Lowercase "mirepoix" in all user-facing text (UI, emails, README, LICENSE body, help site)
- Copyright holder remains Chris Biagini (natural person, not the product)
- Migration 001 edited in place (one-time exception justified in §1.5)
- Historical specs, plans, and memory body text frozen per §1.6
- Jekyll help site \`baseurl\` changes to \`/mirepoix\`; no custom domain in scope

**Not in this PR:**

- O'Saasy license text substitution (separate task #376)
- CLAUDE.md stale-reference sweep beyond brand-swap (separate task)
- Kamal deploy config (belongs to deploy phase)
- ActiveRecord encryption key bootstrap (irreversible, separate task)
- DNS / TLS / VPS provisioning (deploy phase)

**Host-side steps (post-merge, not in this PR):**

1. Rename the GitHub repo \`chris-biagini/familyrecipes\` -> \`chris-biagini/mirepoix\` (web UI)
2. \`git remote set-url origin git@github.com:chris-biagini/mirepoix.git\`
3. \`mv ~/familyrecipes ~/mirepoix\`
4. \`mv ~/.claude/projects/-home-claude-familyrecipes ~/.claude/projects/-home-claude-mirepoix\`

## Test plan

- [x] \`bundle exec rake brand:check_residue\` — clean (new oracle introduced in this PR)
- [x] \`bundle exec rake\` (lint + test + residue check) — passes
- [x] \`bundle exec rake security\` — Brakeman clean
- [x] \`npm run build && npm test\` — clean
- [x] \`bin/dev\` boot smoke test — landing page shows \`<title>mirepoix</title>\`
- [x] Mailer preview shows \`Subject: Sign in to mirepoix\`
- [x] \`Rails.application.class.name\` returns \`Mirepoix::Application\`
- [x] \`Mirepoix::CONFIG[:quick_bites_filename]\` returns \`"Quick Bites.md"\`

## Rollback

PR-level \`git revert\` on the squash commit. Low-risk because the rebrand is mechanical and doesn't change behavior. The GitHub repo rename (post-merge) is reversible via another rename; GitHub preserves redirects forever.
EOF
)"
```

The PR URL will be printed. Return it to the user and stop. The user reviews and merges on GitHub, then runs the host-side steps from the design spec §4.

---

## Self-review checklist

After writing this plan, the following spec requirements were cross-checked for task coverage:

- **§1.1 parser module full rename** → Task 2 (directory + module + references)
- **§1.2 repo/dir/memory rename** → Not in this plan (host-side, post-merge, design spec §4)
- **§1.3 lowercase user-facing** → Tasks 4, 7, 8 (sweep + help site + live docs)
- **§1.4 Chris Biagini copyright** → Task 8 (LICENSE edit notes, preserves holder)
- **§1.5 migration 001 in-place edit** → Task 5 (isolated for audit)
- **§1.6 historical docs frozen** → Every `rg` / `sed` command excludes `docs/superpowers/specs/**` and `docs/superpowers/plans/**`
- **§1.7 help site baseurl** → Task 7 (Jekyll config + topbar + content)
- **§2 code changes** → Tasks 2, 3, 4
- **§3.1 package identity** → Task 6
- **§3.2 build and CI** → Task 6
- **§3.3 help site** → Task 7
- **§3.4 migration** → Task 5
- **§3.5 live project docs** → Task 8
- **§3.6 not modified** → all excludes preserved
- **§6 verification** → Tasks 1 (oracle setup) + 9 (final check)
- **§7 PR strategy** → Task 9 (PR creation)
- **§8 rollback** → Documented in Task 9 PR body

**No placeholders.** Every step has exact commands, file paths, and expected outputs. Find-and-replace operations name the exact sed expressions. The only "find and verify" steps use `rg` with explicit glob excludes.

**Type consistency.** The module constant `Mirepoix` is used consistently (never `mirepoix` in code contexts), and the user-facing string `"mirepoix"` is used consistently (never `"Mirepoix"` in UI contexts). The rake task name `brand:check_residue` is used in Tasks 1 and 9 with the same spelling.
