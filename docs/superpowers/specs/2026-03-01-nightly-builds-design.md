# Nightly Docker Builds

**Issue:** #122
**Date:** 2026-03-01

## Problem

Docker images are only built on version tags or manual dispatch. The developer wants to dog-food the app continuously during early development by running nightly builds that automatically deploy via a homelab cron job.

## Design

Modify `.github/workflows/docker.yml` only. Three additions:

### 1. Schedule trigger

Add a cron schedule to the existing `on:` block. 3 AM US-Eastern is UTC 08:00 (UTC-5 standard) / UTC 07:00 (UTC-4 DST). Use 08:00 to cover the later case.

```yaml
schedule:
  - cron: '0 8 * * *'
```

### 2. Skip-if-unchanged job

A new `check` job runs before `test`. It compares HEAD's SHA against the tags already pushed to GHCR. If the SHA tag already exists, downstream jobs (`test`, `build`) are skipped. This only applies to scheduled runs — tagged releases and manual dispatches always build.

Uses `gh api` to query GHCR package versions, avoiding extra third-party actions.

### 3. Nightly tag

Scheduled builds get an additional `nightly` tag so they're distinguishable from release builds:

```yaml
type=raw,value=nightly,enable=${{ github.event_name == 'schedule' }}
```

## What doesn't change

- Test job still gates the build
- Tagged releases and manual dispatch work identically
- GHCR auth, Buildx, layer caching all untouched
- docker-compose.example.yml pulls `latest`, which nightly builds update
