# Project Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish GitHub Issues as the single source of truth for all project work, with milestones, labels, a pinned tracking issue, and updated docs/memory.

**Architecture:** All changes are GitHub API calls (via `gh` CLI), file edits to CLAUDE.md, the orientation doc, and Claude's memory system. No application code changes.

**Tech Stack:** GitHub CLI (`gh`), markdown

---

## File Structure

- **Modify:** `CLAUDE.md:399-400` — update commit message convention, add project tracking subsection
- **Modify:** `docs/superpowers/specs/2026-04-11-orientation-design.md:137-162` — replace punch list with pointer
- **Create:** `/home/claude/.claude/projects/-home-claude-mirepoix/memory/feedback_gh_source_of_truth.md` — memory entry
- **Modify:** `/home/claude/.claude/projects/-home-claude-mirepoix/memory/project_orientation.md` — update punch list reference
- **Modify:** `/home/claude/.claude/projects/-home-claude-mirepoix/memory/MEMORY.md` — add new memory entry

---

### Task 1: Close stale milestones

Close v0.6–v0.9. Closed issues keep their milestone tags.

**Files:** None (GitHub API only)

- [ ] **Step 1: Close all four milestones**

```bash
gh api repos/:owner/:repo/milestones/4 -X PATCH -f state=closed
gh api repos/:owner/:repo/milestones/3 -X PATCH -f state=closed
gh api repos/:owner/:repo/milestones/2 -X PATCH -f state=closed
gh api repos/:owner/:repo/milestones/1 -X PATCH -f state=closed
```

Milestone numbers: v0.6=#4, v0.7=#3, v0.8=#2, v0.9=#1 (from earlier exploration).

- [ ] **Step 2: Verify**

```bash
gh api repos/:owner/:repo/milestones --jq '.[] | "\(.title) (\(.state))"'
```

Expected: empty (no open milestones) or all show `closed`.

- [ ] **Step 3: Commit** — no file changes; note in commit message.

Not applicable — this task is GitHub API only, no files to commit.

---

### Task 2: Create new milestones

Create `Kamal Deploy` and `Phase 3: Self-Serve`.

**Files:** None (GitHub API only)

- [ ] **Step 1: Create milestones**

```bash
gh api repos/:owner/:repo/milestones -X POST -f title="Kamal Deploy" -f description="Everything before first kamal deploy. When all issues close, we ship."
gh api repos/:owner/:repo/milestones -X POST -f title="Phase 3: Self-Serve" -f description="Gates for opening /new to public self-serve kitchen creation."
```

- [ ] **Step 2: Verify and note milestone numbers**

```bash
gh api repos/:owner/:repo/milestones --jq '.[] | "#\(.number): \(.title)"'
```

Record the milestone numbers — needed for assigning issues in Task 4.

---

### Task 3: Clean up labels

Delete unused defaults, create `ops` label.

**Files:** None (GitHub API only)

- [ ] **Step 1: Delete unused labels**

```bash
gh label delete enhancement --yes
gh label delete documentation --yes
gh label delete wontfix --yes
gh label delete duplicate --yes
gh label delete dependencies --yes
gh label delete ruby --yes
```

- [ ] **Step 2: Create ops label**

```bash
gh label create ops --description "Non-code: infrastructure, DNS, secrets, backups" --color "0E8A16"
```

- [ ] **Step 3: Verify**

```bash
gh label list
```

Expected: `bug`, `ops`, `smelly` (plus any GitHub-managed labels like `invalid`).

---

### Task 4: Assign existing issues to milestones

Move issues into their correct milestones per the spec's issue audit.

**Files:** None (GitHub API only)

- [ ] **Step 1: Assign Kamal Deploy issues**

Use the `Kamal Deploy` milestone number from Task 2 (substitute `KAMAL_MS` below):

```bash
gh issue edit 366 --milestone "Kamal Deploy"
gh issue edit 367 --milestone "Kamal Deploy"
```

- [ ] **Step 2: Assign Phase 3 issues**

```bash
gh issue edit 383 --milestone "Phase 3: Self-Serve"
gh issue edit 384 --milestone "Phase 3: Self-Serve"
```

- [ ] **Step 3: Close #373**

```bash
gh issue close 373 --comment "Completed in PR #385. Auto-close didn't fire because the commit message used 'GH #373' instead of bare '#373'."
```

- [ ] **Step 4: Verify**

```bash
gh issue list --state open --json number,title,milestone --jq '.[] | "#\(.number) \(.title) — \(.milestone.title // "unmilestoned")"'
```

Expected: #366 and #367 in `Kamal Deploy`; #383 and #384 in `Phase 3: Self-Serve`; #364, #382, #386, #387 unmilestoned.

---

### Task 5: Create new issues for ops tasks

Three new issues for work currently tracked only in the orientation doc.

**Files:** None (GitHub API only)

- [ ] **Step 1: Create encryption keys issue**

```bash
gh issue create \
  --title "Bootstrap ActiveRecord encryption keys to 1Password" \
  --label "ops" \
  --milestone "Kamal Deploy" \
  --body "$(cat <<'ISSUE_EOF'
## What

Run `bin/rails db:encryption:init` once. Store the three keys in the "Mirepoix Production" 1Password vault AND print them for physical backup (home safe).

Keys: `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `DETERMINISTIC_KEY`, `KEY_DERIVATION_SALT`.

## Why this matters

These keys cannot be rotated without re-encrypting all data. Encrypted columns (`join_code` et al) become unreadable if the keys are lost. This must happen BEFORE first deploy.

## Procedure

1. `bin/rails db:encryption:init` — generates three values
2. Create "Mirepoix Production" vault in 1Password (if it doesn't exist)
3. Store each key as a separate item in the vault
4. Print the values, place printout in home safe
5. Configure Kamal's 1Password adapter to read from this vault
ISSUE_EOF
)"
```

- [ ] **Step 2: Create DNS/TLS issue**

```bash
gh issue create \
  --title "DNS cut + TLS cert verification" \
  --label "ops" \
  --milestone "Kamal Deploy" \
  --body "$(cat <<'ISSUE_EOF'
## What

Point `mirepoix.recipes` at the Hetzner VPS and verify TLS via Thruster + Let's Encrypt.

## Steps

1. Provision Hetzner Cloud CX22 in Ashburn VA
2. Set A record for `mirepoix.recipes` at Porkbun → VPS public IP
3. Set up SPF + DKIM records for Resend email delivery
4. Deploy with `TLS_DOMAIN=mirepoix.recipes` — Thruster handles Let's Encrypt
5. Verify HTTPS works: `curl -I https://mirepoix.recipes`
6. Verify email: send a test magic link, confirm delivery
ISSUE_EOF
)"
```

- [ ] **Step 3: Create deploy.yml issue**

```bash
gh issue create \
  --title "Write config/deploy.yml for Kamal" \
  --milestone "Kamal Deploy" \
  --body "$(cat <<'ISSUE_EOF'
## What

Create the Kamal deployment configuration. Single server, single role. Starting point: adapt Fizzy's config/deploy.yml per the orientation doc (§3).

## Key decisions (from orientation doc)

- Image: GHCR, renamed after rebrand
- Secrets: 1Password adapter (op CLI on deploy machine, not VPS)
- TLS: Thruster + Let's Encrypt via TLS_DOMAIN
- Volume: Docker named volume at /rails/storage
- Health check: /up endpoint (already exists)
ISSUE_EOF
)"
```

- [ ] **Step 4: Note the new issue numbers**

```bash
gh issue list --milestone "Kamal Deploy" --json number,title --jq '.[] | "#\(.number): \(.title)"'
```

Record these — needed for the tracking issue in Task 6.

---

### Task 6: Create and pin the tracking issue

The critical-path tracking issue for the `Kamal Deploy` milestone.

**Files:** None (GitHub API only)

- [ ] **Step 1: Create the tracking issue**

Substitute the actual issue numbers from Task 5 where indicated (`#ENC`, `#DNS`, `#DEPLOY`):

```bash
gh issue create \
  --title "Kamal Deploy: Critical Path" \
  --milestone "Kamal Deploy" \
  --body "$(cat <<'ISSUE_EOF'
## Critical Path

Ordered by dependency — top items unblock items below them.

- [ ] Move USDA API key to env var (#366)
- [ ] Move Anthropic API key to env var (#367)
- [ ] Write `config/deploy.yml` for Kamal (#DEPLOY)
- [ ] Bootstrap ActiveRecord encryption keys (#ENC, ops)
      ⚠️ Irreversible — keys go to 1Password vault + physical backup
- [ ] `rake release:audit` passes
- [ ] DNS cut + TLS cert verification (#DNS, ops)
- [ ] First `kamal deploy` 🚀

## Maintenance

- Check off items as their linked issues close.
- New blockers get an issue, a milestone, and a line here.
- This issue stays open and pinned until deploy day.
ISSUE_EOF
)"
```

- [ ] **Step 2: Pin the issue**

```bash
gh issue pin <TRACKING_ISSUE_NUMBER>
```

- [ ] **Step 3: Verify**

Open the repo in a browser or:

```bash
gh issue view <TRACKING_ISSUE_NUMBER>
```

Confirm the checklist renders correctly and all issue cross-references link properly.

---

### Task 7: Update CLAUDE.md

Two edits: fix the commit message convention (line 399) and add the project tracking subsection.

**Files:**
- Modify: `CLAUDE.md:399-400` (commit message convention)
- Modify: `CLAUDE.md:340` area (add subsection after Git Strategy)

- [ ] **Step 1: Update commit message convention**

Replace lines 399–400:

```
- Reference GitHub issues in commit messages to auto-close on push
  (e.g., "Resolves #nn" or "Resolves #nn1, resolves #nn2").
```

With:

```
- Reference GitHub issues in commit messages to auto-close on push
  (e.g., "Resolves #123" or "Resolves #123, resolves #124"). Use bare
  `#NNN` — prefixes like `GH #NNN` prevent GitHub's auto-close parser
  from matching.
```

- [ ] **Step 2: Add project tracking subsection**

After the Git Strategy subsection (after the "Key rules" bullet list, before **Screenshots.**), add:

```markdown
### Project Tracking — GitHub Issues is the source of truth

**Milestoned issues = committed work.** `Kamal Deploy` and
`Phase 3: Self-Serve` contain shaped, actionable issues. The pinned
tracking issue in each active milestone shows the critical path in
dependency order.

**Unmilestoned issues = idea pile.** Quick notes, half-baked bugs,
tinkering candidates. Zero commitment. Promoting to a milestone is a
deliberate act.

**Labels:** `bug`, `smelly`, `ops` (non-code tasks). No label = normal
code work.

**Convention:** When a session discovers new work, file an issue. When
a session completes work, close the issue and check off the tracking
issue line. Don't maintain competing task lists in design docs, memory,
or CLAUDE.md.
```

- [ ] **Step 3: Verify lint**

```bash
bundle exec rubocop CLAUDE.md 2>/dev/null || true
```

CLAUDE.md is markdown — RuboCop won't lint it, but verify no syntax issues by reading the file.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
Add project tracking conventions to CLAUDE.md

Establishes GitHub Issues as the single source of truth. Adds a
Project Tracking subsection to Workflow and clarifies commit message
syntax for auto-close (bare #NNN, not GH #NNN).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Update orientation doc

Replace the §3 punch list checkboxes with a pointer to the tracking issue.

**Files:**
- Modify: `docs/superpowers/specs/2026-04-11-orientation-design.md:137-162`

- [ ] **Step 1: Replace the punch list**

Replace lines 137–162 (from `### Pre-deploy punch list` through the "Soon after dogfood is stable" items) with:

```markdown
### Pre-deploy punch list

Tracked in the pinned **"Kamal Deploy: Critical Path"** issue in the
`Kamal Deploy` milestone. That issue is the single source of truth for
what's left before first deploy — don't maintain a competing checklist
here.

Completed prior to this change: rebrand (#378), O'Saasy license (#379),
CLAUDE.md sweep, MEMORY.md update, superseded spec annotation.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-04-11-orientation-design.md
git commit -m "$(cat <<'EOF'
Point orientation doc punch list at GitHub tracking issue

Replaces the inline checkbox list with a pointer to the pinned
"Kamal Deploy: Critical Path" issue. One source of truth.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Update memory system

New feedback memory for GH conventions. Update orientation memory to reflect the punch list change.

**Files:**
- Create: `/home/claude/.claude/projects/-home-claude-mirepoix/memory/feedback_gh_source_of_truth.md`
- Modify: `/home/claude/.claude/projects/-home-claude-mirepoix/memory/project_orientation.md`
- Modify: `/home/claude/.claude/projects/-home-claude-mirepoix/memory/MEMORY.md`

- [ ] **Step 1: Create feedback memory**

Write to `/home/claude/.claude/projects/-home-claude-mirepoix/memory/feedback_gh_source_of_truth.md`:

```markdown
---
name: GitHub Issues is the single source of truth
description: All work tracked in GitHub Issues — milestoned = committed, unmilestoned = idea pile. No competing lists.
type: feedback
---

GitHub Issues is the single source of truth for all project work — code, ops, and ideas.

**Why:** Work was scattered across the orientation doc's punch list, GitHub Issues, and Claude's memory. None were complete or consistent, and sessions started with confusion about what was next.

**How to apply:**
- When a session discovers new work, file a GitHub issue.
- When a session completes work, close the issue and check off the tracking issue line.
- Don't maintain competing task lists in design docs, memory, or CLAUDE.md.
- Milestoned issues are committed work; unmilestoned are the idea pile.
- Labels: `bug`, `smelly`, `ops`. No label = normal code work.
- Commit messages: use bare `#NNN` for auto-close (not `GH #NNN` or `issue #NNN`).
```

- [ ] **Step 2: Update orientation memory**

In `/home/claude/.claude/projects/-home-claude-mirepoix/memory/project_orientation.md`, append to the end (before the `## Authoritative references` section if present, or at the very end):

```markdown

**Punch list update (2026-04-12):** The orientation doc's §3 punch list
now points at the pinned "Kamal Deploy: Critical Path" GitHub issue
instead of maintaining its own checkboxes. GitHub Issues is the single
source of truth per `docs/superpowers/specs/2026-04-12-project-tracking-design.md`.
```

- [ ] **Step 3: Update MEMORY.md index**

Add a line to the Feedback section of MEMORY.md:

```markdown
- [GitHub Issues is source of truth](feedback_gh_source_of_truth.md) — milestoned = committed, unmilestoned = ideas, bare #NNN in commits
```

- [ ] **Step 4: Verify memory files**

Read back both memory files and MEMORY.md to confirm correct formatting and no duplicates.

---

### Task 10: Final verification and commit plan

- [ ] **Step 1: Verify GitHub state**

```bash
# Milestones
gh api repos/:owner/:repo/milestones --jq '.[] | "\(.title) (\(.state)) — \(.open_issues) open"'

# Labels
gh label list

# Open issues with milestones
gh issue list --state open --json number,title,milestone,labels --jq '.[] | "#\(.number) \(.title) — \(.milestone.title // "unmilestoned") [\(.labels | map(.name) | join(", "))]"'

# Pinned issue
gh issue list --state open --json number,title,isPinned --jq '.[] | select(.isPinned) | "#\(.number) \(.title)"'
```

- [ ] **Step 2: Verify file changes**

```bash
git log --oneline feature/project-tracking --not main
```

Expected: design spec commit, CLAUDE.md commit, orientation doc commit (3 commits after the spec).

- [ ] **Step 3: Push and open PR**

```bash
git push -u origin feature/project-tracking
gh pr create --title "Establish GitHub Issues as single source of truth" --body "$(cat <<'EOF'
## Summary

- Closes stale milestones (v0.6–v0.9), creates `Kamal Deploy` and `Phase 3: Self-Serve`
- Cleans up labels: keeps `bug`/`smelly`, adds `ops`, deletes unused defaults
- Audits all open issues into milestones (or idea pile)
- Creates new ops issues for encryption keys, DNS/TLS, deploy.yml
- Pins a "Kamal Deploy: Critical Path" tracking issue with dependency-ordered checklist
- Adds Project Tracking subsection to CLAUDE.md
- Points orientation doc punch list at the tracking issue

## Test plan

- [ ] Open the repo on GitHub — pinned tracking issue visible at top
- [ ] Click into `Kamal Deploy` milestone — all deploy-blocking issues present
- [ ] Click into `Phase 3: Self-Serve` milestone — #383 and #384 present
- [ ] Verify #373 is closed with explanatory comment
- [ ] Verify stale milestones (v0.6–v0.9) are closed
- [ ] Verify labels: only `bug`, `smelly`, `ops` remain

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
