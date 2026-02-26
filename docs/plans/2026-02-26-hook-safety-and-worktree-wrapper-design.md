# Hook Safety and Worktree Wrapper

**Date:** 2026-02-26

## Problems

### 1. Merge commits bypass timestamp privacy

The `post-commit` hook rewrites commit timestamps for privacy, but `git merge`
does not trigger `post-commit`. All merge commits in the repo retain real
timestamps with local timezone offsets, defeating the privacy goal.

A `post-merge` hook can cover this gap, but `git commit --amend` fails inside
`post-merge` because git still has `MERGE_HEAD` state present. The workaround
is to remove `MERGE_HEAD` before amending — this is safe because the merge
commit is already finalized by the time `post-merge` fires.

### 2. Worktree cleanup bricks the Bash tool

When a Claude Code session runs inside a git worktree, removing that worktree
deletes the Bash tool's CWD. Once the CWD is gone, every subsequent Bash
command fails for the rest of the session. This has happened multiple times
despite being documented in both CLAUDE.md and project memory.

The root cause is that the mitigation is a convention ("always cd first") that
relies on the agent remembering to do it. Conventions that rely on memory fail
under cognitive load.

## Solution

### Part 1: post-merge hook

`post-merge` removes `MERGE_HEAD` then delegates to `post-commit` via `exec`.
Single source of truth for timestamp logic.

**Why removing MERGE_HEAD is safe:** `post-merge` fires after the merge commit
is complete and recorded. `MERGE_HEAD` is residual state that git cleans up
momentarily; removing it early just unblocks `--amend`. The merge commit's
parents are already recorded in the commit object and are not affected.

### Part 2: CWD guard in post-commit

A guard near the top of `post-commit` checks whether the CWD still exists. If a
worktree was removed and something triggers a commit from a deleted CWD, the
hook bails gracefully instead of producing confusing errors.

### Part 3: bin/worktree-remove

A tracked wrapper script that encodes the "cd to repo root first" convention as
executable code. It:

1. Resolves the repository root via `git rev-parse --show-toplevel`
2. Accepts a worktree path or name argument
3. `cd`s to the repo root before removing
4. Runs `git worktree remove` + `git worktree prune`
5. Prints confirmation

CLAUDE.md references this script instead of raw git commands. The script is
committed to the repo and survives clones.

## What this does NOT do

- Does not prevent `git worktree remove` from being run directly
- Does not change worktree creation
- Does not add complexity beyond what's needed

## Files changed

- `.git/hooks/post-merge` — new hook (untracked, manual install)
- `.git/hooks/post-commit` — add CWD guard (untracked, manual install)
- `bin/worktree-remove` — new tracked script
- `CLAUDE.md` — update worktree cleanup section
