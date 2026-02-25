# Quality Review: Multi-User Chaotic Testing

**Date:** 2026-02-25

## Overview

Deep quality review via Playwright browser automation simulating 3 concurrent users interacting with all app pages. Goal: discover rendering glitches, JS errors, state bugs, race conditions, and edge cases.

## Approach

### Users
- 3 separate users created in the database, each with kitchen membership
- Each user gets their own Playwright browser context

### Phases

1. **Setup & Serial Baseline** — Start server, create users, serial page walkthrough for obvious issues
2. **Functional Testing** — Each agent tests assigned pages methodically (valid input)
3. **Malformed Input** — XSS payloads, empty strings, long text, special characters, missing fields
4. **Concurrent Stress** — All 3 agents on groceries page simultaneously, testing ActionCable sync
5. **Rapid-Fire** — Faster-than-human speed on all interactive controls, checking for race conditions

### Issue Handling
- Fix in-session: < 30 lines of changes
- GitHub issue: > 30 lines or needs design decisions

## Pages Under Test

| Page | Key Controls |
|------|-------------|
| Homepage | Recipe links, +New recipe editor |
| Recipe | Edit/delete, scale, cross-off, cross-references |
| Groceries | Recipe selection, custom items, check/uncheck, Quick Bites editor, aisle order editor, ActionCable sync |
| Ingredients | Nutrition editor, reset, aisle assignment |
