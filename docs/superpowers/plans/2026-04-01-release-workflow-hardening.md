# Release Workflow Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix bugs and simplify the three-tier release notes system — harden the GitHub Actions workflow, delete the fragile Claude Code hook, and replace it with a CLAUDE.md convention.

**Architecture:** The release system has three components today: a GitHub Actions workflow (`docker.yml`), a Claude Code PostToolUse hook (`.claude/hooks/post-tag-push.sh`), and settings that wire the hook up (`.claude/settings.local.json`). The hook parses bash command text to detect tag pushes — inherently fragile. We're deleting it and moving the "draft release notes" convention into CLAUDE.md, where Claude already reads it. The workflow gets hardened with bug fixes.

**Tech Stack:** GitHub Actions, bash, `gh` CLI

---

### Task 1: Harden the GitHub Actions release workflow

The `Create GitHub Release` step in `docker.yml` has several bugs: shallow checkout means `git tag`/`git log` can't see history, regex dot in grep matches wrong tags, four-part tags silently get wrong tier, suffix tags aren't handled, and the changelog link is broken for first releases.

**Files:**
- Modify: `.github/workflows/docker.yml:19-129`

- [ ] **Step 1: Add full checkout depth**

The checkout step (line 19-20) needs `fetch-depth: 0` so the release step can see all tags and commit history.

Change the checkout step from:

```yaml
      - name: Checkout
        uses: actions/checkout@v4
```

to:

```yaml
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
```

- [ ] **Step 2: Rewrite the Create GitHub Release step**

Replace the entire `Create GitHub Release` step (lines 95-129) with hardened logic that:
1. Strips optional letter suffixes before classifying (`v0.5.4a` → patch, same as `v0.5.4`)
2. Explicitly rejects four-part tags (`v0.6.8.1`) — skips release creation with a warning
3. Uses `grep -Fx` (fixed-string, whole-line) instead of regex grep to find previous tag — avoids the `.` wildcard bug
4. Finds previous tag of any format (not just same-tier tags)
5. Caps commit log at 100 entries to handle first-ever tag gracefully
6. Omits the "Full Changelog" comparison link when there's no previous tag

```yaml
      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ github.ref_name }}
          REPO: ${{ github.repository }}
        run: |
          # Strip optional letter suffix for classification (v0.5.4a → v0.5.4)
          BASE_TAG=$(echo "$TAG" | sed 's/[a-zA-Z]*$//')

          # Reject four-part tags (v0.6.8.1) — build the image but skip release
          if echo "$BASE_TAG" | grep -qE '^v[0-9]+(\.[0-9]+){3,}$'; then
            echo "::warning::Skipping release for unsupported tag format: $TAG"
            exit 0
          fi

          # Classify: vX.Y.Z = patch, vX.Y = minor, vX = major
          if echo "$BASE_TAG" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            TIER="patch"
          elif echo "$BASE_TAG" | grep -qE '^v[0-9]+\.[0-9]+$'; then
            TIER="minor"
          elif echo "$BASE_TAG" | grep -qE '^v[0-9]+$'; then
            TIER="major"
          else
            echo "::warning::Skipping release for unrecognized tag format: $TAG"
            exit 0
          fi

          echo "Tag: $TAG (base: $BASE_TAG, tier: $TIER)"

          # Find previous tag — use fixed-string whole-line match to avoid regex dot bug
          PREV_TAG=$(git tag --sort=-v:refname | grep -Fx -A1 "$TAG" | tail -1)

          if [ "$PREV_TAG" = "$TAG" ] || [ -z "$PREV_TAG" ]; then
            RANGE="$TAG"
          else
            RANGE="${PREV_TAG}..${TAG}"
          fi

          # Generate commit list (cap at 100 to handle first-ever tag gracefully)
          git log --format="- %s" --no-merges -100 "$RANGE" > /tmp/release-notes.md

          # Add changelog comparison link only when a previous tag exists
          if [ "$RANGE" != "$TAG" ]; then
            echo "" >> /tmp/release-notes.md
            echo "**Full Changelog**: https://github.com/${REPO}/compare/${PREV_TAG}...${TAG}" >> /tmp/release-notes.md
          fi

          DRAFT_FLAG=""
          if [ "$TIER" != "patch" ]; then
            DRAFT_FLAG="--draft"
          fi

          gh release create "$TAG" $DRAFT_FLAG --notes-file /tmp/release-notes.md
```

- [ ] **Step 3: Review the complete workflow file**

Read `.github/workflows/docker.yml` end-to-end and verify:
- The checkout step has `fetch-depth: 0`
- The release step has the new classification logic
- No other steps reference tag classification or assume shallow checkout
- YAML indentation is correct (2-space indent under `run: |`)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/docker.yml
git commit -m "Harden release workflow: deep checkout, suffix/four-part tags, grep -Fx"
```

### Task 2: Delete the Claude Code hook

The PostToolUse hook parses bash command text to detect tag pushes — inherently fragile. Delete it and its settings registration. The release notes convention moves to CLAUDE.md in Task 3.

**Files:**
- Delete: `.claude/hooks/post-tag-push.sh`
- Modify: `.claude/settings.local.json`

- [ ] **Step 1: Delete the hook script**

```bash
rm .claude/hooks/post-tag-push.sh
```

Verify the `.claude/hooks/` directory is now empty (or doesn't exist). If other hooks exist, leave them alone.

- [ ] **Step 2: Remove the hooks section from settings**

Edit `.claude/settings.local.json` to remove the entire `"hooks"` key, leaving only `"permissions"`. The file should become:

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(bundle exec:*)",
      "Bash(ruby:*)",
      "Bash(gh issue:*)",
      "Bash(gh release:*)",
      "WebFetch(domain:codemirror.net)"
    ]
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A .claude/hooks/ .claude/settings.local.json
git commit -m "Remove post-tag-push hook: replace with CLAUDE.md convention"
```

### Task 3: Update CLAUDE.md releases section

Replace the hook-based release notes documentation with a convention that Claude follows from CLAUDE.md instructions. Also remove the now-stale reference to "a Claude Code hook fires on push."

**Files:**
- Modify: `CLAUDE.md:380-392`

- [ ] **Step 1: Rewrite the Releases paragraph**

Replace lines 380-392 of `CLAUDE.md` (the `**Releases.**` paragraph) with:

```markdown
**Releases.** Tag pushes trigger `docker.yml`: build → smoke test (`/up`
health check) → push to GHCR → create GitHub Release. Three tiers based on
tag format (optional letter suffix like `a` is stripped before classifying):
- **Patch** (`vX.Y.Z`): auto-published with commit bullet list.
- **Minor** (`vX.Y`): draft release. After pushing, wait for the CI
  workflow to create the draft (`gh release view TAG`), then write curated
  release notes organized by theme (features, fixes, polish) and update
  via `gh release edit TAG --notes-file <file>`.
- **Major** (`vX`): draft release. After pushing, wait for the CI workflow
  to create the draft, then write marketing-quality release notes with
  sections: Highlights, Breaking changes, What's new, Fixes, Upgrade
  notes. Update via `gh release edit TAG --notes-file <file>`.
- Four-part tags (`vX.Y.Z.W`) are not supported — CI skips release
  creation for these.
The `REVISION` build arg bakes the version into the image (read by
`ApplicationHelper#app_version`). Only tag when code is known-good —
in-between commits on main are not built. The pre-push hook runs lint on
all files (~5s); tests run exclusively in CI.
```

- [ ] **Step 2: Verify no other CLAUDE.md references to the hook**

Search `CLAUDE.md` for "hook fires", "post-tag-push", "PostToolUse", or "release notes hook". Remove or update any stale references found.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md: convention-based release notes, document suffix/four-part tags"
```
