# Help Site Dark Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `prefers-color-scheme: dark` support to the Jekyll help site.

**Architecture:** A single `@media (prefers-color-scheme: dark)` block appended to `docs/help/assets/style.css`. Every hardcoded light-mode color gets an override. No JS, no CSS variables, no markup changes.

**Tech Stack:** CSS media queries, Jekyll static site

**Spec:** `docs/superpowers/specs/2026-04-01-help-site-dark-mode-design.md`

---

### Task 1: Add dark mode overrides to style.css

**Files:**
- Modify: `docs/help/assets/style.css` (append after line 337)

The entire implementation is one CSS block. The overrides are organized to mirror the existing stylesheet's section structure for easy cross-reference.

**Dark palette (zinc scale):**
- Page bg: `#18181b`, surfaces: `#27272a`, borders: `#3f3f46`
- Primary text: `#fafafa`, body: `#d4d4d8`, muted: `#a1a1aa`
- Accent: `#c0522a` (unchanged), inline code text: `#d4835a` (lifted for contrast)
- Code blocks: `#2e2b28` (lifted from `#1e1b18`)

- [ ] **Step 1: Append the dark mode media query block**

Add this block at the end of `docs/help/assets/style.css`:

```css
/* ── Dark mode ─────────────────────────────────────────── */
@media (prefers-color-scheme: dark) {
  body {
    background: #18181b;
    color: #d4d4d8;
  }

  /* ── Topbar ── */
  .topbar {
    background: #27272a;
    border-bottom-color: #3f3f46;
  }
  .topbar-name { color: #fafafa; }
  .topbar-sub {
    color: #a1a1aa;
    border-left-color: #3f3f46;
  }

  /* ── Sidebar ── */
  .sidebar {
    background: #27272a;
    border-right-color: #3f3f46;
  }
  .sidebar-section-label { color: #a1a1aa; }
  .sidebar-link { color: #a1a1aa; }
  .sidebar-link:hover {
    color: #c0522a;
    background: rgba(192, 82, 42, 0.1);
  }
  .sidebar-link.active {
    color: #c0522a;
    background: rgba(192, 82, 42, 0.1);
  }
  .sidebar-divider { background: #3f3f46; }

  /* ── Typography ── */
  h1, h2 { color: #fafafa; }
  h3 { color: #d4d4d8; }
  p { color: #d4d4d8; }
  p.lead { color: #a1a1aa; }
  ul, ol { color: #d4d4d8; }

  /* ── Links ── */
  a { color: #c0522a; }

  /* ── Code ── */
  code {
    background: #27272a;
    color: #d4835a;
  }
  pre {
    background: #2e2b28;
  }

  /* ── Breadcrumb ── */
  .breadcrumb { color: #a1a1aa; }

  /* ── Callout ── */
  .callout {
    background: #27272a;
    border-color: #3f3f46;
    border-left-color: #c0522a;
  }
  .callout p { color: #d4d4d8; }

  /* ── Page nav ── */
  .page-nav { border-top-color: #3f3f46; }

  /* ── Section cards ── */
  .section-card {
    background: #27272a;
    border-color: #3f3f46;
  }
  .section-card:hover {
    border-color: #c0522a;
    box-shadow: 0 2px 8px rgba(192, 82, 42, 0.15);
  }
  .section-card h3 { color: #fafafa; }
  .section-card p { color: #a1a1aa; }

  /* ── Tables ── */
  th {
    background: #27272a;
    border-bottom-color: #3f3f46;
    color: #d4d4d8;
  }
  td {
    border-bottom-color: #3f3f46;
    color: #d4d4d8;
  }

  /* ── Mobile ── */
  .nav-toggle { color: #d4d4d8; }
  .nav-toggle:hover { background: #3f3f46; }
  .nav-backdrop { background: rgba(0, 0, 0, 0.5); }
}
```

- [ ] **Step 2: Build the Jekyll site and verify**

```bash
cd /tmp && jekyll build --source ~/familyrecipes/docs/help --destination ~/familyrecipes/_site
```

Expected: Build succeeds with no errors.

- [ ] **Step 3: Spot-check contrast**

Open the built CSS and verify:
- Inline code text `#d4835a` on `#27272a` background meets WCAG AA (4.5:1 minimum). Calculated contrast ratio is ~4.7:1 — passes.
- Body text `#d4d4d8` on `#18181b` background. Contrast ratio ~12.8:1 — passes easily.
- Muted text `#a1a1aa` on `#18181b`. Contrast ratio ~7.2:1 — passes.

- [ ] **Step 4: Commit**

```bash
git add docs/help/assets/style.css
git commit -m "Add dark mode to help site

Uses prefers-color-scheme media query with zinc neutral palette.
No JS, no toggle — follows OS preference automatically."
```
