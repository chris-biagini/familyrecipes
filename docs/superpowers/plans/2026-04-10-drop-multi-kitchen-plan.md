# Drop MULTI_KITCHEN Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the `MULTI_KITCHEN` env var and everything it gated — a single-kitchen validation, a controller before-action, a test helper, and ~30 test call sites — without disturbing the sole-kitchen URL convenience or trusted-header auth.

**Architecture:** Pure deletion + mechanical test unwrap. The single-kitchen validation goes away (kitchens can always be created in multiples); the controller gate goes away (creation becomes ungated, consistent with Phase 1 of the auth plan which will re-gate via email verification in Phase 2); all tests that wrapped blocks in `with_multi_kitchen` get unwrapped. No behavioral change for the common case because the sole-kitchen URL convenience (`resolve_sole_kitchen`) is unrelated and stays.

**Tech Stack:** Rails 8, Minitest, RuboCop, Brakeman. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-04-10-trusted-header-and-multi-kitchen-cleanup-design.md` (PR 1 section).

**Branch:** `feature/drop-multi-kitchen` (already created).

---

## File Structure

**Files to modify:**

- `app/models/kitchen.rb` — remove `enforce_single_kitchen_mode` validation and its private method
- `app/controllers/kitchens_controller.rb` — remove `require_multi_kitchen_mode` before-action and its private method
- `test/test_helper.rb` — remove `with_multi_kitchen` helper method
- `test/models/kitchen_test.rb` — delete 3 tests tied to the removed validation; unwrap 1 `with_multi_kitchen` call
- 20 other test files — unwrap `with_multi_kitchen` blocks (mechanical, see Task 3)
- `lib/tasks/release_audit.rake` — strip `MULTI_KITCHEN=true` from 4 locations
- `test/security/seed_security_kitchens.rb` — update comments only
- `test/release/exploratory/accessibility.spec.mjs` — update comment
- `test/release/exploratory/setup.mjs` — update comment
- `CLAUDE.md` — 3 references

**Files not touched:**

- `app/controllers/application_controller.rb` — `resolve_sole_kitchen` and `authenticate_from_headers` are untouched by this PR
- `config/routes.rb` — routing scope is untouched; sole-kitchen convenience stays
- `README.md` — grep found no `MULTI_KITCHEN` references; verified at Task 7
- Historical spec/plan docs under `docs/superpowers/` — past-state artifacts, left alone

---

## Task 1: Remove `enforce_single_kitchen_mode` validation from `Kitchen`

**Files:**
- Modify: `app/models/kitchen.rb`
- Modify: `test/models/kitchen_test.rb`

This task removes the validation and the three tests that exercised it. Two of those tests become meaningless when the validation is gone (they tested "first kitchen is allowed" and "updating existing kitchen is allowed" — both trivially true without the validation). The third tested the rejection path and must go. A fourth test ("allows second kitchen") is renamed and unwrapped — it's a useful regression check that multiple kitchens coexist without a gate.

- [ ] **Step 1: Delete the three obsolete tests and rewrite the fourth**

Open `test/models/kitchen_test.rb`. Find the block of tests starting at line 118:

```ruby
  test 'allows first kitchen when multi_kitchen is false' do
    ActsAsTenant.without_tenant { Kitchen.destroy_all }
    kitchen = Kitchen.new(name: 'First', slug: 'first')

    assert_predicate kitchen, :valid?
  end

  test 'blocks second kitchen when multi_kitchen is false' do
    second = Kitchen.new(name: 'Second', slug: 'second')

    assert_not second.valid?
    assert_includes second.errors[:base], 'Only one kitchen is allowed in single-kitchen mode'
  end

  test 'allows second kitchen when multi_kitchen is true' do
    with_multi_kitchen do
      second = Kitchen.new(name: 'Second', slug: 'second')

      assert_predicate second, :valid?
    end
  end

  test 'allows updating existing kitchen when multi_kitchen is false' do
    @kitchen.name = 'Updated'

    assert_predicate @kitchen, :valid?
  end
```

Replace that entire block with a single regression test:

```ruby
  test 'allows multiple kitchens to coexist' do
    second = Kitchen.new(name: 'Second', slug: 'second')

    assert_predicate second, :valid?
  end
```

- [ ] **Step 2: Run the kitchen model test file — it should still pass (the validation being removed is in Step 3)**

Run: `ruby -Itest test/models/kitchen_test.rb`

Expected: 1 failure — `allows multiple kitchens to coexist` fails because the validation is still present. This is the failing test for the removal work; the validation removal in Step 3 will turn it green.

- [ ] **Step 3: Remove the validation from `app/models/kitchen.rb`**

Delete line 90 (the `validate` line) and the private method at lines 152–157:

```ruby
  validate :enforce_single_kitchen_mode, on: :create
```

and

```ruby
  def enforce_single_kitchen_mode
    return if ENV['MULTI_KITCHEN'] == 'true'

    # Intentionally unscoped — checking global kitchen count, not tenant-scoped data
    errors.add(:base, 'Only one kitchen is allowed in single-kitchen mode') if Kitchen.exists?
  end
```

- [ ] **Step 4: Run the kitchen model tests again — all should pass**

Run: `ruby -Itest test/models/kitchen_test.rb`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/kitchen.rb test/models/kitchen_test.rb
git commit -m "Drop single-kitchen-mode validation from Kitchen

Part of #363. With passwordless auth shipped, per-kitchen membership
is always available, so the capacity gate is obsolete. Collapses the
four tests tied to the validation into one regression check that
multiple kitchens can coexist.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Remove `require_multi_kitchen_mode` from `KitchensController`

**Files:**
- Modify: `app/controllers/kitchens_controller.rb`

Kitchen creation becomes ungated. This is consistent with Phase 1 of the auth spec (which explicitly calls it "ungated in Phase 1"); Phase 2 will re-gate via email verification.

- [ ] **Step 1: Remove the before-action and its private method**

In `app/controllers/kitchens_controller.rb`, delete line 14:

```ruby
  before_action :require_multi_kitchen_mode, only: %i[new create]
```

And delete the private method at lines 68–72:

```ruby
  def require_multi_kitchen_mode
    return if ENV['MULTI_KITCHEN'] == 'true' || ActsAsTenant.without_tenant { Kitchen.none? }

    redirect_to root_path, alert: 'Kitchen creation is not enabled.'
  end
```

- [ ] **Step 2: Update the controller header comment**

The current header says "Ungated in Phase 1 (beta); Phase 2 adds email verification for hosted mode." That line stays — it's still accurate. No other changes to the comment.

- [ ] **Step 3: Run the controller tests — they should still use `with_multi_kitchen` at this point, and still pass (the helper now has no effect but is still defined)**

Run: `ruby -Itest test/controllers/kitchens_controller_test.rb`

Expected: all tests pass. The `with_multi_kitchen` helper still exists at this point and is still a no-op wrapper, so nothing breaks.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/kitchens_controller.rb
git commit -m "Drop require_multi_kitchen_mode from KitchensController

Part of #363. Kitchen creation becomes ungated in Phase 1, matching
the auth spec. Phase 2 will re-gate with email verification.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Unwrap `with_multi_kitchen` call sites across the test suite

**Files:**
- Modify: 21 test files (enumerated below)

30 call sites, all mechanical. The pattern is: find `with_multi_kitchen do`, delete that line and its matching `end`, outdent the body by two spaces. Do not remove the helper definition yet — that's Task 4. Removing it here would break every untouched file midway through.

**The unwrap pattern, shown once:**

Before:
```ruby
test 'some behavior' do
  with_multi_kitchen do
    Kitchen.create!(name: 'X', slug: 'x')
    assert_predicate Kitchen.last, :valid?
  end
end
```

After:
```ruby
test 'some behavior' do
  Kitchen.create!(name: 'X', slug: 'x')
  assert_predicate Kitchen.last, :valid?
end
```

For multi-line bodies, every line of the body outdents by exactly two spaces. No other changes.

**File list with call-site counts:**

Controller tests (14 call sites in 9 files):
- `test/controllers/kitchens_controller_test.rb` — 5 call sites
- `test/controllers/transfers_controller_test.rb` — 2 call sites
- `test/controllers/header_auth_test.rb` — 1 call site
- `test/controllers/joins_controller_test.rb` — 1 call site
- `test/controllers/landing_controller_test.rb` — 1 call site
- `test/controllers/tenant_isolation_test.rb` — 1 call site
- `test/controllers/auth_test.rb` — 1 call site
- `test/controllers/groceries_controller_test.rb` — 1 call site
- `test/controllers/pwa_controller_test.rb` — 1 call site

Model tests (15 call sites in 11 files):
- `test/models/kitchen_test.rb` — 2 call sites (note: Task 1 deleted the third occurrence; these two are in different tests)
- `test/models/kitchen_join_code_test.rb` — 2 call sites
- `test/models/cook_history_entry_test.rb` — 2 call sites
- `test/models/ingredient_catalog_test.rb` — 2 call sites
- `test/models/recipe_model_test.rb` — 1 call site
- `test/models/category_test.rb` — 1 call site
- `test/models/custom_grocery_item_test.rb` — 1 call site
- `test/models/meal_plan_selection_test.rb` — 1 call site
- `test/models/on_hand_entry_test.rb` — 1 call site
- `test/models/quick_bite_test.rb` — 1 call site
- `test/models/tag_test.rb` — 1 call site

Service tests (1 call site in 1 file):
- `test/services/aisle_write_service_test.rb` — 1 call site

- [ ] **Step 1: Unwrap all 30 call sites**

Work through the file list above. For each file: open it, find every `with_multi_kitchen do` block (the Grep output has line numbers), unwrap following the pattern above, save.

- [ ] **Step 2: Verify zero `with_multi_kitchen do` call sites remain in the test directory**

Run grep via the Grep tool:
- pattern: `with_multi_kitchen do`
- path: `test/`

Expected: no matches. If any remain, unwrap them before proceeding.

(The helper definition itself at `test/test_helper.rb:99` will still match a broader `with_multi_kitchen` grep — that is expected and will be removed in Task 4.)

- [ ] **Step 3: Run the full test suite**

Run: `bundle exec rake test`

Expected: all tests pass. 1961+ runs, 0 failures, 0 errors.

If a test fails because a `with_multi_kitchen` block was missed, the error will be a `NameError` pointing at the exact file and line — fix it by unwrapping that block too.

- [ ] **Step 4: Run RuboCop**

Run: `bundle exec rake lint`

Expected: 0 offenses. Indentation after unwrapping should be clean.

- [ ] **Step 5: Commit**

```bash
git add test/controllers test/models test/services
git commit -m "Unwrap with_multi_kitchen blocks in test suite

Part of #363. 30 call sites across 21 files, all mechanical. Helper
definition itself is removed in the next commit.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Remove the `with_multi_kitchen` helper

**Files:**
- Modify: `test/test_helper.rb`

- [ ] **Step 1: Delete the helper definition**

In `test/test_helper.rb`, delete lines 99–105:

```ruby
    def with_multi_kitchen
      original = ENV.fetch('MULTI_KITCHEN', nil)
      ENV['MULTI_KITCHEN'] = 'true'
      yield
    ensure
      ENV['MULTI_KITCHEN'] = original
    end
```

- [ ] **Step 2: Verify zero `with_multi_kitchen` references remain in `test/`**

Grep: pattern `with_multi_kitchen`, path `test/`.

Expected: no matches.

- [ ] **Step 3: Run the full test suite**

Run: `bundle exec rake test`

Expected: all tests pass. Any failure here means a call site was missed in Task 3 — the test file will now throw `NoMethodError` for `with_multi_kitchen`. Fix by unwrapping the missed site.

- [ ] **Step 4: Commit**

```bash
git add test/test_helper.rb
git commit -m "Remove with_multi_kitchen test helper

Part of #363. Last MULTI_KITCHEN reference in test code.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Strip `MULTI_KITCHEN=true` from release audit rake task

**Files:**
- Modify: `lib/tasks/release_audit.rake`

Four occurrences: one in an env hash that gets passed to `system(...)`, three in `puts` strings that tell the operator how to start the dev server.

- [ ] **Step 1: Update the security seed invocation**

In `lib/tasks/release_audit.rake`, line 105:

Before:
```ruby
      unless system({ 'MULTI_KITCHEN' => 'true' }, 'bin/rails runner test/security/seed_security_kitchens.rb')
```

After:
```ruby
      unless system('bin/rails runner test/security/seed_security_kitchens.rb')
```

- [ ] **Step 2: Update the three `puts` strings**

Three lines currently read `puts 'NOTE: Requires a running dev server (MULTI_KITCHEN=true bin/dev)'` — at approximately lines 126, 141, and 153. Update each to:

```ruby
      puts 'NOTE: Requires a running dev server (bin/dev)'
```

- [ ] **Step 3: Verify no `MULTI_KITCHEN` references remain in the rake file**

Grep: pattern `MULTI_KITCHEN`, path `lib/tasks/release_audit.rake`.

Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add lib/tasks/release_audit.rake
git commit -m "Strip MULTI_KITCHEN=true from release audit rake task

Part of #363. Security seed and dev-server hints no longer need the
env var — it is being removed entirely.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Update script comments referencing `MULTI_KITCHEN`

**Files:**
- Modify: `test/security/seed_security_kitchens.rb`
- Modify: `test/release/exploratory/accessibility.spec.mjs`
- Modify: `test/release/exploratory/setup.mjs`

Pure comment updates — no functional change.

- [ ] **Step 1: `test/security/seed_security_kitchens.rb`**

The header comment currently says:

```ruby
# Seeds two isolated kitchens for security testing. Run via:
#   MULTI_KITCHEN=true bin/rails runner test/security/seed_security_kitchens.rb
```

and later:

```ruby
# Note: set MULTI_KITCHEN=true for multi-kitchen routing to work.
```

Update to:

```ruby
# Seeds two isolated kitchens for security testing. Run via:
#   bin/rails runner test/security/seed_security_kitchens.rb
```

Delete the "Note: set MULTI_KITCHEN=true..." line entirely.

- [ ] **Step 2: `test/release/exploratory/accessibility.spec.mjs`**

The file has two top-of-file comments referencing the env var:

```javascript
// Requires a running dev server: MULTI_KITCHEN=true bin/dev
// Requires security kitchens seeded: MULTI_KITCHEN=true bin/rails runner test/security/seed_security_kitchens.rb
```

Update to:

```javascript
// Requires a running dev server: bin/dev
// Requires security kitchens seeded: bin/rails runner test/security/seed_security_kitchens.rb
```

- [ ] **Step 3: `test/release/exploratory/setup.mjs`**

Line 2 comment reads:

```javascript
// Assumes a running dev server on localhost:3030 with MULTI_KITCHEN=true.
```

Update to:

```javascript
// Assumes a running dev server on localhost:3030.
```

- [ ] **Step 4: Verify no `MULTI_KITCHEN` references remain in the three files**

Grep: pattern `MULTI_KITCHEN`, glob `test/security/*.rb` and `test/release/exploratory/*.mjs`.

Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add test/security/seed_security_kitchens.rb test/release/exploratory/accessibility.spec.mjs test/release/exploratory/setup.mjs
git commit -m "Drop MULTI_KITCHEN=true hints from script comments

Part of #363.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

Three references. One is a sentence in the Architecture section; two are inside code fences showing commands.

- [ ] **Step 1: Remove the "multi_kitchen is an env var" sentence from the write-path section**

At approximately line 188, find:

```
Read write service header comments for details. `multi_kitchen` is an env
var, not a DB setting. Background jobs: `RecipeNutritionJob` recomputes
```

Remove the "`multi_kitchen` is an env var, not a DB setting." sentence. The surrounding lines become:

```
Read write service header comments for details. Background jobs:
`RecipeNutritionJob` recomputes
```

Re-flow the paragraph if needed so line length stays consistent with surrounding prose (~80 chars).

- [ ] **Step 2: Update the security pen test command block**

At approximately line 278, find:

```bash
MULTI_KITCHEN=true bin/rails runner test/security/seed_security_kitchens.rb
```

Change to:

```bash
bin/rails runner test/security/seed_security_kitchens.rb
```

- [ ] **Step 3: Update the release audit section**

At approximately line 319, find:

```
(< 48h) audit marker matching HEAD. Tier 3 requires a running dev server
(`MULTI_KITCHEN=true bin/dev`). Config: `config/release_audit.yml`,
```

Change to:

```
(< 48h) audit marker matching HEAD. Tier 3 requires a running dev server
(`bin/dev`). Config: `config/release_audit.yml`,
```

- [ ] **Step 4: Verify no `MULTI_KITCHEN` references remain in `CLAUDE.md`**

Grep: pattern `MULTI_KITCHEN|multi_kitchen`, path `CLAUDE.md`.

Expected: no matches.

- [ ] **Step 5: Check README.md**

Grep: pattern `MULTI_KITCHEN|multi_kitchen`, path `README.md`.

Expected: no matches. If any are found, update them following the same pattern as CLAUDE.md. (The initial grep said none exist, but verify before committing.)

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "Remove MULTI_KITCHEN references from CLAUDE.md

Part of #363.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Final verification

**Files:** none modified

- [ ] **Step 1: Full grep for any remaining `MULTI_KITCHEN` or `multi_kitchen` references**

Grep: pattern `MULTI_KITCHEN|multi_kitchen`, path `.` (repo root).

Expected matches should ONLY be in `docs/superpowers/specs/` and `docs/superpowers/plans/` (historical design docs that document past state, intentionally untouched). Anything else is a miss and must be cleaned up.

- [ ] **Step 2: Full test suite**

Run: `bundle exec rake test`

Expected: all tests pass. ~1961 runs. 0 failures, 0 errors.

- [ ] **Step 3: Lint**

Run: `bundle exec rake lint`

Expected: 0 offenses.

- [ ] **Step 4: Brakeman security scan**

Run: `bundle exec rake security`

Expected: no new warnings compared to the baseline on `main`.

- [ ] **Step 5: Manual smoke test — sole-kitchen URL convenience still works**

Start the dev server: `bin/dev`

In a browser, navigate to `http://rika:3030/`. Expected: the landing page loads. If signed in with an existing test user, navigating to `/recipes` should show the recipe list at the bare URL (not slug-prefixed) because `resolve_sole_kitchen` is still routing to the sole kitchen.

Stop the server with Ctrl-C when done.

- [ ] **Step 6: Manual smoke test — creating a second kitchen switches to slug-prefixed routing**

With the dev server running, visit `http://rika:3030/new`. Create a second kitchen with a different name (e.g., "Test Two"). After creation, the post-create redirect should land at `http://rika:3030/kitchens/test-two/` (slug-prefixed). Verify the first kitchen now also serves under its slug at `http://rika:3030/kitchens/<original-slug>/`.

(Optional teardown: in a rails console, `Kitchen.find_by(slug: 'test-two').destroy` to restore single-kitchen state.)

Stop the server.

- [ ] **Step 7: Push the branch and open the PR**

```bash
git push -u origin feature/drop-multi-kitchen
gh pr create --title "Drop MULTI_KITCHEN flag (#363)" --body "$(cat <<'EOF'
## Summary

- Removes the `MULTI_KITCHEN` env var and everything it gated: a Kitchen
  validation, a KitchensController before-action, a test helper, and
  ~30 test call sites
- Keeps `resolve_sole_kitchen` (URL convenience) and
  `authenticate_from_headers` (trusted-header path) — both untouched
- Kitchen creation becomes ungated in Phase 1, matching the auth spec.
  Phase 2 will re-gate via email verification.

Spec: `docs/superpowers/specs/2026-04-10-trusted-header-and-multi-kitchen-cleanup-design.md` (PR 1 section). PR 2 (#365 hardening) ships on a separate branch after this merges.

Resolves #363.

## Test plan

- [ ] `bundle exec rake test` — full suite green
- [ ] `bundle exec rake lint` — 0 offenses
- [ ] `bundle exec rake security` — no new Brakeman findings
- [ ] Manual: single-kitchen install still routes to bare URLs
- [ ] Manual: creating a second kitchen switches to slug-prefixed routing
- [ ] Manual: trusted-header auto-join still works for the sole-kitchen case

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review Notes

**Spec coverage:**
- Model change (remove validation) → Task 1 ✓
- Controller change (remove before-action) → Task 2 ✓
- Test helper removal + call-site unwrap → Tasks 3 and 4 ✓
- `enforce_single_kitchen_mode` test deletion → Task 1 ✓
- Release audit rake task → Task 5 ✓
- Security seed / exploratory spec comments → Task 6 ✓
- CLAUDE.md → Task 7 ✓
- README.md grep check → Task 7 Step 5 ✓
- Verification: `rake test`, `rake release:audit:full`, smoke tests → Task 8 ✓
- Historical docs untouched (intentional per spec) → noted in Task 8 Step 1 ✓

**Risks reiterated from spec:**
- Missed `with_multi_kitchen` call site → caught at Task 3 Step 3 (rake test) with `NameError`, backstop at Task 4 Step 3 (rake test) with `NoMethodError`, final grep at Task 8 Step 1.
