# AI Import Dual Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Expert mode toggle to AI import — faithful (default) preserves source wording, expert condenses for experienced cooks.

**Architecture:** Two prompt files, one service with mode parameter, checkbox in UI, ralph loop for expert prompt tuning.

**Tech Stack:** Ruby/Rails, Stimulus JS, Anthropic SDK

---

### Task 1: Rename faithful prompt and restore tags
### Task 2: Create expert prompt
### Task 3: Update AiImportService for dual mode
### Task 4: Update AiImportController for mode param
### Task 5: Update JS controller and dialog UI
### Task 6: Update tests
### Task 7: Update ralph loop tooling
### Task 8: Run expert prompt ralph loop
### Task 9: Copy tuned prompts to production, final tests
