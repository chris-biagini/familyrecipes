# Commit Timestamp Privacy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Install a post-commit hook that rewrites commit timestamps to obscure time-of-day while preserving calendar date and chronological order.

**Architecture:** A bash post-commit hook in `.githooks/` amends each commit's author and committer dates to a monotonically increasing UTC time, starting at noon with jitter for each new day. An environment variable guard prevents infinite recursion from the amend.

**Tech Stack:** Bash (POSIX-compatible with GNU/BSD date fallbacks), Git hooks

---

### Task 1: Write the post-commit hook

**Files:**
- Create: `.githooks/post-commit`

**Step 1: Create the `.githooks` directory**

Run: `mkdir -p .githooks`

**Step 2: Write the hook script**

Create `.githooks/post-commit` with this exact content:

```bash
#!/usr/bin/env bash
#
# Rewrites commit timestamps for privacy. Preserves the calendar date,
# replaces time-of-day with a monotonically increasing synthetic time.

# Guard: the amend below re-triggers post-commit. Bail on the second pass.
[ -n "$GIT_PRIVACY_AMENDING" ] && exit 0
export GIT_PRIVACY_AMENDING=1

# --- Helpers for GNU/BSD date portability ---

epoch_from_iso() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S" "$1" +%s
}

iso_from_epoch() {
  date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S +0000" 2>/dev/null || date -u -r "$1" +"%Y-%m-%dT%H:%M:%S +0000"
}

# --- Extract current commit's calendar date (UTC) ---

orig_author_date=$(git log -1 --format='%aI')
commit_day=$(echo "$orig_author_date" | cut -dT -f1)

# --- Check parent commit's timestamp ---

parent_date=$(git log -1 --skip=1 --format='%aI' 2>/dev/null)
parent_day=""
parent_epoch=0

if [ -n "$parent_date" ]; then
  parent_day=$(echo "$parent_date" | cut -dT -f1)
  parent_epoch=$(epoch_from_iso "$(echo "$parent_date" | sed 's/ *[+-][0-9]*$//' | sed 's/T/ /')")
fi

# --- Generate the private timestamp ---

if [ "$commit_day" = "$parent_day" ] && [ "$parent_epoch" -gt 0 ]; then
  # Same day as parent: advance by 2-20 minutes
  if command -v shuf > /dev/null 2>&1; then
    gap=$(shuf -i 120-1200 -n 1)
  else
    gap=$(( (RANDOM % 1081) + 120 ))
  fi
  new_epoch=$(( parent_epoch + gap ))
else
  # New day: start at noon UTC +/- 3 hours
  noon_epoch=$(epoch_from_iso "${commit_day}T12:00:00")
  if command -v shuf > /dev/null 2>&1; then
    jitter=$(shuf -i 0-21600 -n 1)
  else
    jitter=$(( RANDOM % 21601 ))
  fi
  jitter=$(( jitter - 10800 ))
  new_epoch=$(( noon_epoch + jitter ))
fi

# Clamp to 23:00 UTC on the commit day to avoid rolling into next day
max_epoch=$(epoch_from_iso "${commit_day}T23:00:00")
if [ "$new_epoch" -gt "$max_epoch" ]; then
  new_epoch=$max_epoch
fi

private_date=$(iso_from_epoch "$new_epoch")

# --- Amend the commit with the private timestamp ---

GIT_COMMITTER_DATE="$private_date" \
git commit --amend --no-edit --no-verify --allow-empty \
  --date="$private_date" \
  > /dev/null 2>&1
```

**Step 3: Make the hook executable**

Run: `chmod +x .githooks/post-commit`

**Step 4: Smoke test the hook manually**

Run: `bash -n .githooks/post-commit` to check for syntax errors.
Expected: no output (clean parse).

**Step 5: Commit the hook**

```bash
git add .githooks/post-commit
git commit -m "chore: add post-commit hook for timestamp privacy"
```

Note: This commit itself will NOT be amended because `core.hooksPath` hasn't been
set yet. The hook is tracked but inactive at this point.

---

### Task 2: Activate the hook and verify

**Step 1: Set core.hooksPath**

Run: `git config core.hooksPath .githooks`

This is a local-only config change (`.git/config`), not tracked in the repo.

**Step 2: Make a test commit**

Create a temporary file and commit it:

```bash
echo "test" > /tmp/privacy-test.txt
cp /tmp/privacy-test.txt .git/privacy-test-marker
git commit --allow-empty -m "test: verify timestamp privacy hook"
```

**Step 3: Verify the timestamp was rewritten**

Run: `git log -1 --format='%aI %cI'`

Expected: Both dates should show `+00:00` timezone (UTC) and a time near noon
(between 09:00 and 15:00 UTC), NOT the actual local time.

**Step 4: Verify monotonic ordering with a second commit**

```bash
git commit --allow-empty -m "test: verify monotonic timestamp ordering"
git log -2 --format='%aI %cI'
```

Expected: The second commit's time should be 2-20 minutes after the first.
Both should be UTC.

**Step 5: Clean up test commits**

```bash
git reset --soft HEAD~2
```

This removes the two test commits but keeps the working tree clean.

---

### Task 3: Update CLAUDE.md with setup instructions

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add a section to CLAUDE.md under Workflow Preferences**

Add after the "GitHub Issues" section, before "## Database Setup":

```markdown
### Commit timestamp privacy
This repo uses a post-commit hook (`.githooks/post-commit`) that rewrites
commit timestamps for privacy. After cloning, activate it:
```bash
git config core.hooksPath .githooks
```
The hook replaces time-of-day with synthetic UTC timestamps while preserving
the calendar date and chronological commit order. See
`docs/plans/2026-02-23-commit-privacy-design.md` for details.
```

**Step 2: Commit the CLAUDE.md update**

```bash
git add CLAUDE.md
git commit -m "docs: add timestamp privacy setup to CLAUDE.md"
```

**Step 3: Verify the commit was sanitized**

Run: `git log -1 --format='%aI %cI'`

Expected: UTC timezone, synthetic time. This is the first "real" commit that
the hook processes.
