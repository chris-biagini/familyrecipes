# XSS Fix: Escape Unsanitized HTML in Recipe Rendering

**Issue:** #85
**Date:** 2026-02-24
**Approach:** Renderer-level escaping (Approach A)

## Problem

The Redcarpet `SmartyHTML` renderer is initialized without `escape_html: true`.
Combined with `.html_safe` calls in `RecipesHelper` and views, raw HTML in recipe
markdown passes through to the browser unescaped. A kitchen member could inject
arbitrary JavaScript into recipe pages, affecting all viewers.

## Vulnerability Surface

Four layers:

1. **Renderer** — `SmartyHTML.new` lacks `escape_html: true`
2. **RecipesHelper** — `render_markdown`, `format_yield_line`, `format_yield_with_unit`
   mark output `.html_safe`
3. **ScalableNumberPreprocessor** — builds HTML via string interpolation with unescaped
   user content in data attributes (`build_span`, `process_yield_with_unit`)
4. **Views** — `_step.html.erb` line 19 and `_nutrition_table.html.erb` line 16 mark
   user-controlled values `.html_safe`

## Design

### 1. Renderer fix

Add `escape_html: true` to the `SmartyHTML` renderer in `lib/familyrecipes/recipe.rb`:

```ruby
MARKDOWN = Redcarpet::Markdown.new(
  Redcarpet::Render::SmartyHTML.new(escape_html: true),
  autolink: true,
  no_intra_emphasis: true
)
```

Redcarpet escapes all raw HTML tags before rendering markdown syntax. Markdown-generated
HTML (`**bold**` to `<strong>`) still works because those are produced by the renderer
after escaping. The `.html_safe` call in `render_markdown` remains correct.

### 2. ScalableNumberPreprocessor fix

Use `ERB::Util.html_escape` on every user-controlled value before interpolating into HTML:

- **`build_span`** — escape `original_text` before placing it in `data-original-text`
  and the tag body
- **`process_yield_with_unit`** — escape `unit_singular` and `unit_plural` before placing
  them in `data-unit-singular` and `data-unit-plural` attributes

The `.html_safe` calls in `format_yield_line` and `format_yield_with_unit` remain valid
because the preprocessor now produces safe output.

### 3. View-level fixes

Two `.html_safe` calls need fixing:

- **`_step.html.erb` line 19** — `data-quantity-unit-plural` attribute interpolates
  `Inflector.unit_display(item.quantity_unit, 2)` without escaping. Fix: escape the
  value before interpolation.
- **`_nutrition_table.html.erb` line 16** — `"Per Serving<br>(...)"` interpolates
  `formatted_ups` and `ups_unit` from recipe front matter. Fix: escape both values
  before interpolation; the `<br>` is intentional HTML.

Two other `.html_safe` calls are safe and need no changes:

- Line 49: `indent` is a hardcoded integer (0, 1, or 2)
- Line 52: `key` is from a literal array, `value` goes through `.to_f.round`

### 4. Testing

New file `test/integration/xss_prevention_test.rb` with these cases:

1. `<script>` tag in recipe instructions — verify escaped in rendered output
2. `<img onerror=...>` in step title — verify escaped in `<h2>`
3. `<script>` in front matter unit noun — verify escaped in yield display and
   nutrition table column header
4. Quote-breaking payload in ingredient quantity unit — verify escaped in
   `data-quantity-unit-plural` attribute
5. `<script>` in recipe footer — verify escaped in rendered footer

Tests use `MarkdownImporter` to create recipes from malicious markdown, then hit the
recipe show page and inspect the response body for escaped output.

## Files Changed

- `lib/familyrecipes/recipe.rb` — add `escape_html: true`
- `lib/familyrecipes/scalable_number_preprocessor.rb` — escape user values in `build_span`
  and `process_yield_with_unit`
- `app/views/recipes/_step.html.erb` — escape `quantity_unit` in data attribute
- `app/views/recipes/_nutrition_table.html.erb` — escape `formatted_ups` and `ups_unit`
- `test/integration/xss_prevention_test.rb` — new XSS prevention tests

## Decision: No HTML allowed in recipe markdown

All HTML in recipe markdown is treated as untrusted and escaped. Markdown syntax provides
sufficient formatting (bold, italic, links, etc.). No allowlist/sanitization needed.
