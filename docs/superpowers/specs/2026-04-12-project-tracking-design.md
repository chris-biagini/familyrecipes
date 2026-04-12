# Project Tracking: GitHub Issues as Single Source of Truth

*Design spec for organizing all project work — code, ops, and ideas — in
GitHub Issues with minimal ceremony.*

## Problem

Three places claimed to be the roadmap: the orientation doc's punch list,
GitHub Issues, and Claude's memory system. None were complete or consistent.
Issues lacked milestones and labels, ops tasks existed only in prose, and
there was no way to open GitHub and see the critical path at a glance.

## Decisions

### Milestones

Two milestones, plus the implicit idea pile:

- **`Kamal Deploy`** — everything that must be done before `kamal deploy`.
  When every issue here is closed, we deploy.
- **`Phase 3: Self-Serve`** — gates for opening `/new` to the public.
  Not active yet; issues land here when we know they belong.
- **No milestone** — the idea pile. Quick notes, half-baked bugs, tinkering
  candidates. Zero commitment. Promoting to a milestone is a deliberate act.

Close the four stale milestones (v0.6–v0.9). Closed issues retain their
milestone tags for history.

### Labels

Minimal taxonomy — the milestone says *when*, the label says *what kind*:

- **`bug`** — something isn't working (keep, already in use)
- **`smelly`** — code smell worth fixing (keep, already in use)
- **`ops`** — non-code tasks: infrastructure, DNS, secrets, backups (new)

No label = normal code work. No status labels, no priority labels.

Delete unused defaults: `enhancement`, `documentation`, `wontfix`,
`duplicate`, `dependencies`, `ruby`.

### Issue audit

**Assign to `Kamal Deploy`:**
- #366 — Move USDA API key to env var
- #367 — Move Anthropic API key to env var
- New: Bootstrap ActiveRecord encryption keys (`ops`)
- New: DNS cut + TLS cert verification (`ops`)
- New: Write `config/deploy.yml` for Kamal

**Assign to `Phase 3: Self-Serve`:**
- #383 — Per-account rate limits for hosted deployment
- #384 — Promote MagicLink.cleanup_expired to Solid Queue

**Leave unmilestoned (idea pile):**
- #382 — Sign out everywhere button
- #386 — Pantry tab for inventory management
- #387 — Rails convention audit
- #364 — Join code UX (regenerate commits immediately)

**Close as completed:**
- #373 — Security audit (work done in PR #385; `GH #373` prefix in commit
  message prevented auto-close)

**Already done (no action needed):**
Orientation doc punch list items 1–5 (rebrand, O'Saasy license, CLAUDE.md
sweep, MEMORY.md update, superseded annotation) were completed in prior
sessions. They don't need GitHub issues — they're just history.

### Pinned tracking issue

A single issue titled **"Kamal Deploy: Critical Path"** in the `Kamal Deploy`
milestone, pinned to the repo. Body is a dependency-ordered markdown checklist
linking to individual issues. Each line is a one-liner — detail lives in the
linked issue, not here.

Content:

```markdown
## Critical Path

Ordered by dependency — top items unblock items below them.

- [ ] Move USDA API key to env var (#366)
- [ ] Move Anthropic API key to env var (#367)
- [ ] Write `config/deploy.yml` for Kamal (#NNN)
- [ ] Bootstrap ActiveRecord encryption keys (#NNN, ops)
      ⚠️ Irreversible — keys go to 1Password vault + physical backup
- [ ] `rake release:audit` passes
- [ ] DNS cut + TLS cert verification (#NNN, ops)
- [ ] First `kamal deploy` 🚀

## Maintenance
- Check off items as their linked issues close.
- New blockers get an issue, a milestone, and a line here.
- This issue stays open and pinned until deploy day.
```

Issue numbers for new issues (`#NNN`) are filled in during implementation
after the issues are created.

### Orientation doc update

Replace the §3 punch list checkboxes with a pointer to the tracking issue.
Keep the strategic prose and infrastructure details — they're context that
doesn't belong in GitHub issues.

### CLAUDE.md update

Add a "Project tracking" subsection to the Workflow section:

> **Project tracking.** GitHub Issues is the single source of truth for all
> work — code, ops, and ideas. Milestoned issues are committed work;
> unmilestoned issues are the idea pile. The pinned tracking issue in each
> active milestone shows the critical path in dependency order. Don't maintain
> competing task lists in design docs, memory, or CLAUDE.md. When a session
> discovers new work, file an issue. When a session completes work, close the
> issue and check off the tracking issue line.

### Commit message convention

Clarify the existing CLAUDE.md bullet about issue references:

> Reference GitHub issues in commit messages to auto-close on push
> (e.g., "Resolves #123" or "Resolves #123, resolves #124"). Use bare
> `#NNN` — prefixes like `GH #NNN` or `issue #NNN` prevent GitHub's
> auto-close parser from matching.

### Memory updates

- New `feedback` memory: GitHub Issues is the single source of truth.
  Don't maintain competing task lists. Commit messages use bare `#NNN`
  for auto-close.
- Update `project_orientation.md` memory to note the punch list now lives
  in the GitHub tracking issue, not the orientation doc.

## Out of scope

- GitHub Projects boards — more ceremony than a 1.5-person team needs
- Fizzy or any external tool — one tool, one source of truth
- Sprint planning, estimates, due dates — we work top-to-bottom on the
  tracking issue
- Automated issue templates — not enough volume to justify
