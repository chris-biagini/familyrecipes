# Help Icons Design

**Date:** 2026-03-26
**Status:** Approved

## Overview

Add contextual help ("?") icons throughout the app that link to the relevant
section of the GitHub Pages help site. The nav bar gets a persistent icon; all
editor dialogs get one in the header.

Help site base URL: `https://chris-biagini.github.io/familyrecipes`

---

## Infrastructure

### `ApplicationHelper`

Add a `HELP_BASE_URL` constant and a `help_url(path)` method:

```ruby
HELP_BASE_URL = 'https://chris-biagini.github.io/familyrecipes'

def help_url(path)
  "#{HELP_BASE_URL}#{path}"
end
```

### Icon

Add a `help` entry to `IconHelper::ICONS` — a circled question mark, stroke
style matching existing icons:

```ruby
help: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
        content: '<circle cx="12" cy="12" r="9"/>' \
                 '<path d="M9.5 9.5a2.5 2.5 0 0 1 5 0c0 2-2.5 2.5-2.5 4.5"/>' \
                 '<path d="M12 17.5h.01"/>' }
```

### CSS

Add `.nav-help-link` to `navigation.css`, mirroring `.nav-settings-link`
(same sizing, hover colour, padding).

---

## Nav Bar

In `_nav.html.erb`, add a help link after the settings button. It only renders
when the current view has set a help path via `content_for`:

```erb
<% if content_for?(:help_path) %>
  <a href="<%= help_url(yield(:help_path)) %>"
     class="nav-help-link"
     title="Help"
     aria-label="Help"
     target="_blank"
     rel="noopener noreferrer">
    <%= icon(:help, class: 'nav-icon', size: nil) %>
  </a>
<% end %>
```

### Page mappings (`content_for(:help_path)` in each view)

| View | Help path |
|---|---|
| `homepage/show.html.erb` | `/recipes/` |
| `recipes/show.html.erb` | `/recipes/` |
| `menu/show.html.erb` | `/menu/` |
| `groceries/show.html.erb` | `/groceries/` |
| `ingredients/index.html.erb` | `/ingredients/` |

---

## Editor Dialog Partial

`_editor_dialog.html.erb` gets an optional `help_path: nil` local. When
present, a `?` link is rendered in `editor-header-actions`, left of the close
button:

```erb
<%# locals: (title:, id:, dialog_data: {}, footer_extra: nil, extra_data: {}, mode_toggle: false, help_path: nil) %>
```

In the header actions block:

```erb
<% if help_path %>
  <a href="<%= help_url(help_path) %>"
     class="editor-help-link"
     title="Help"
     aria-label="Help"
     target="_blank"
     rel="noopener noreferrer">
    <%= icon(:help, size: 14) %>
  </a>
<% end %>
```

### Dialog mappings (`help_path:` local at each call site)

| Dialog | Call site | Help path |
|---|---|---|
| New Recipe | `homepage/show.html.erb` | `/recipes/editing/` |
| Categories | `homepage/show.html.erb` | `/recipes/tags-and-categories/` |
| Tags | `homepage/show.html.erb` | `/recipes/tags-and-categories/` |
| Edit Recipe | `recipes/show.html.erb` | `/recipes/editing/` |
| Edit Nutrition (recipe) | `recipes/show.html.erb` | `/recipes/nutrition/` |
| Edit Nutrition (ingredients) | `ingredients/index.html.erb` | `/ingredients/nutrition-data/` |
| QuickBites editor | `menu/show.html.erb` | `/menu/quickbites/` |
| Aisles | `groceries/show.html.erb` | `/groceries/aisles/` |
| Settings | `settings/_dialog.html.erb` | `/settings/` |

### AI Import dialog

The AI import dialog is a custom `<dialog>` (not using `_editor_dialog`).
Add the `?` link manually in its header actions, same pattern, pointing to
`/import-export/ai-import/`.

---

## CSS for dialog help button

Add `.editor-help-link` to `editor.css` — a small ghost icon button, same style as
`.editor-mode-toggle` (no background, subtle border on hover). Note: `.editor-help`
already exists in editor.css as a text-copy style; use `.editor-help-link` for the
button to avoid collision.

---

## Help docs

No structural changes required. All target URLs already exist in the deployed
help site. Verify each URL resolves during implementation.

---

## What is NOT in scope

- No help icons in the mobile nav drawer (the drawer mirrors nav links, not
  utility buttons)
- No help icons on error or empty-state pages
- No tooltip or popover — plain `<a target="_blank">` only
