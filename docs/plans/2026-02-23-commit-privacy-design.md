# Commit Timestamp Privacy

**Date:** 2026-02-23

## Problem

Git commits store two timestamps (author date and committer date), each with a
timezone offset. These reveal when and roughly where the committer works. Over a
repository's lifetime, this builds an activity profile: working hours, timezone,
and day-of-week patterns. Push timestamps are also visible but cannot be
controlled client-side and are less granular (one push covers many commits).

## Goal

Obscure time-of-day information in commit timestamps while preserving:

- **Calendar date** — which day the work happened on.
- **Relative chronological order** — commits read sequentially in `git log`.
- **Natural appearance** — casual observers should not immediately notice the
  timestamps are synthetic.

## Approach: Post-Commit Hook with Monotonic Timestamps

A `post-commit` hook in `.githooks/post-commit` rewrites both `GIT_AUTHOR_DATE`
and `GIT_COMMITTER_DATE` immediately after each commit.

### Timestamp generation

1. Extract the **calendar date** from the original commit's author date.
2. Check the **parent commit's timestamp**:
   - If the parent is on the **same calendar day** (and already sanitized), set
     the new timestamp to `parent_time + random_gap` where the gap is 2-20
     minutes.
   - If the parent is on a **different day** (or this is the first commit), use
     **noon UTC with jitter of +/- 3 hours** (range: 09:00-15:00 UTC).
3. Clamp at 23:00 UTC to prevent rolling into the next calendar day.
4. All timestamps use **UTC (+0000)** to prevent timezone leakage.

This produces monotonically increasing, naturally spaced timestamps that look
like a normal work session: 9:14, 9:27, 9:38, 9:51, 10:08...

### Recursion guard

The hook amends the commit, which triggers `post-commit` again. An environment
variable (`GIT_PRIVACY_AMENDING`) prevents infinite recursion. The hook checks
for this variable and exits immediately on the second invocation.

### Cross-platform compatibility

The `date` command differs between GNU (Linux) and BSD (macOS). The hook handles
both with fallback syntax.

## Repo setup

- Hook stored at `.githooks/post-commit` (tracked in the repository).
- Activated via `git config core.hooksPath .githooks` (one-time local setup).
- Documented in CLAUDE.md so the setup step is not forgotten.

## Scope

- **This repository only.** Not a global git config change.
- **Going forward only.** Existing commit history retains its original
  timestamps. Rewriting would change all hashes and require a force push.

## What this covers

- All commits made locally (manual, Claude Code, GUI clients, IDE integrations).
- Merge commits (via `post-merge` hook) and rebase results.
- User-initiated `--amend` operations (the hook fires on the result).

## What this does not cover

- **Push timestamps** — GitHub records when pushes arrive. Not controllable
  client-side.
- **GitHub Actions timestamps** — CI workflow runs have real timestamps.
- **Commit frequency** — the number of commits per day remains visible.
- **Existing history** — the ~200+ commits already pushed retain real timestamps
  with `-0500` offsets.

## Edge cases

- **Very prolific days**: 50 commits averaging 10-minute gaps would end around
  17:00 UTC from a 09:00 start. Well within normal bounds. The 23:00 clamp is a
  safety net.
- **CI environments**: The hook only activates when `core.hooksPath` is
  configured locally. CI/GitHub Actions do not run it unless explicitly set up.
- **GPG-signed commits**: The amend invalidates the signature. Not currently
  relevant to this repo but worth noting.
