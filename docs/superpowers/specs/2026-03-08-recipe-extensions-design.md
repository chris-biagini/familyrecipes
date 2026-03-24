# Recipe .md and .html Extensions

GitHub issue: #205

## Summary

Add two easter-egg endpoints per recipe that serve raw and rendered content
outside the normal app UI:

- `/recipes/scrambled-eggs.md` → raw markdown source (`text/plain; charset=utf-8`)
- `/recipes/scrambled-eggs.html` → Redcarpet-rendered HTML in a minimal document (`text/html; charset=utf-8`)

No links in the UI. No styling or JS in the HTML output.

## Routing

Two explicit routes above the `resources :recipes` line so they match first:

```ruby
get 'recipes/:slug.md', to: 'recipes#show_markdown', as: :recipe_markdown
get 'recipes/:slug.html', to: 'recipes#show_html', as: :recipe_html
```

These live inside the existing `(/kitchens/:kitchen_slug)` scope for multi-tenant support.

## Controller

Two new actions on `RecipesController`:

**`show_markdown`** — finds recipe by slug, sends `markdown_source` verbatim
as `text/plain; charset=utf-8`.

**`show_html`** — finds recipe by slug, renders `markdown_source` through
Redcarpet, wraps in a minimal HTML document:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Recipe Title</title>
</head>
<body>
  <!-- redcarpet output -->
</body>
</html>
```

No app layout, no styles, no JS.

## Redcarpet Configuration

Basic extensions: `tables`, `fenced_code_blocks`, `autolink`. Custom `>>>`
cross-reference syntax renders as plain text — no special handling.

## Testing

Controller tests for each action:
- 200 with correct content type
- `.md` body matches `markdown_source` verbatim
- `.html` body contains rendered HTML within the minimal document skeleton
- 404 for unknown slugs

## Out of Scope

- No UI links to these endpoints (easter eggs only)
- No caching headers
- No cross-reference syntax handling in rendered HTML
