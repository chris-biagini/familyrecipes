# Write Path Simplification

## Problem

RecipeWriteService has four nearly identical public methods — `create`/`create_from_structure`
and `update`/`update_from_structure` — that duplicate transaction ceremony, tag sync, rename
cascades, and finalization. The duplication exists because the graphical editor emits an IR hash
while the text editor emits markdown, and both paths were kept separate end-to-end.

The deeper issue: `markdown_source` was originally stored as the source of truth so the user's
original input could be recovered. But the system has evolved past that:

- Views render from AR records, never from markdown.
- The editor `content` endpoint regenerates markdown from AR via `RecipeSerializer`, not from
  the stored `markdown_source`.
- The graphical editor works with IR derived from AR records.
- Other `markdown_source` readers (`ExportService`, `CrossReferenceUpdater`, `show_markdown`/
  `show_html` endpoints, version-hash digests in views) can all generate on demand.

AR records are already the de facto source of truth. The code should reflect that.

## Design

### Architectural shift

Drop the `markdown_source` column. AR records are the sole source of truth. Markdown is a
serialization format generated on demand by `RecipeSerializer`.

### Component changes

**`MarkdownImporter`:**

- `import(markdown, kitchen:, category:)` — parse markdown to IR, then delegate to shared
  `run` method. No longer stores the markdown string.
- `import_from_structure(ir_hash, kitchen:, category:)` — pass IR directly to `run`. No longer
  serializes to markdown first (the current code serializes the IR to markdown just to store it
  in a column we're dropping).
- `run` / `save_recipe` / `update_recipe_attributes` — remove `markdown_source:` from the
  attribute assignment.
- Constructor drops the `markdown_source` positional argument on the structure path. Internally,
  `@parsed` (the IR hash) is the only state needed for saving.

**`RecipeWriteService`:**

- `create_from_structure(structure:)` becomes a thin normalizer: extracts `category_name` and
  `tags` from `structure[:front_matter]`, then delegates to `create(markdown: nil, structure:,
  ...)` or a shared private method.
- `update_from_structure(slug:, structure:)` — same pattern.
- The four-method duplication collapses. `import_structure_and_timestamp` is deleted.
- Public API stays backward-compatible: callers still call `create`/`create_from_structure`
  with the same arguments.

**`CrossReferenceUpdater`:**

- `update_referencing_recipes` currently reads `ref_recipe.markdown_source` to do string
  substitution on `@[Old Title]` → `@[New Title]`, then re-imports. After dropping the column,
  it generates markdown on demand via `RecipeSerializer` before performing the substitution.
  The re-import via `MarkdownImporter.import` still works — it parses the substituted markdown
  and saves updated AR records.

**`ExportService`:**

- `add_recipes` changes from `recipe.markdown_source` to generating markdown via
  `RecipeSerializer.from_record(recipe)` → `RecipeSerializer.serialize(ir)`.

**`RecipesController`:**

- `#content` — already generates markdown from AR via the serializer. No change needed.
- `#show_markdown` — generates markdown on demand via `RecipeSerializer` instead of reading
  `recipe.markdown_source`.
- `#show_html` — same: generates markdown via serializer, then renders to HTML.

**Views:**

- `recipes/show.html.erb` and `recipes/_embedded_recipe.html.erb` compute a version hash via
  `Digest::SHA256.hexdigest(recipe.markdown_source)` for `recipe_state_controller` cache
  invalidation. Switch to `recipe.updated_at.to_s` (or `edited_at.to_s`).

**`Recipe` model:**

- Remove `validates :markdown_source, presence: true`.
- Update header comment.

**Migration:**

- `005_drop_markdown_source.rb`: `remove_column :recipes, :markdown_source, :text`

**Param naming (not in scope):**

The `editor_body_key: 'markdown_source'` in views and JS controllers is an HTTP param name,
not a column reference. Renaming it would touch views, JS controllers, and Rails controllers
for no functional benefit. Left as-is.

### Validation

Parser validation (rejecting malformed markdown) stays on the text editor path — the parser
is the on-ramp for unstructured text. AR model validations (title presence, etc.) cover both
paths. The graphical editor's UI constrains input to valid structures.

Parser strictness improvements (warning on unrecognized lines instead of silently dropping)
are tracked separately in GH #245.

### What doesn't change

- `RecipeSerializer` — no changes, already works correctly.
- `RecipesController#content` — already regenerates from AR.
- `RecipesController#parse` / `#serialize` — mode-switching endpoints unchanged.
- `MarkdownValidator` — still validates text editor input before save.
- `editor_body_key` / `markdown_source` param names in JS and views — HTTP param, not column.

### Testing

- **MarkdownImporter tests**: remove `markdown_source` assertions. Parse → AR round-trip
  assertions stay.
- **RecipeWriteService tests**: structure path tests simplify. Verify both paths produce
  identical AR records.
- **ExportService tests**: assertions on exported markdown content now validate serializer
  output. Update expected strings if serializer formatting differs from previously stored
  markdown.
- **ImportService tests**: import → export round-trip tests are the most important — they
  validate that parser and serializer are faithful inverses.
- **Controller tests**: drop `markdown_source` assertions from recipe CRUD tests.
- **Migration**: CI verifies `db:create db:migrate db:seed` from scratch.

### Files touched

| File | Change |
|------|--------|
| `db/migrate/005_drop_markdown_source.rb` | New migration |
| `app/services/markdown_importer.rb` | Remove markdown storage, simplify structure path |
| `app/services/recipe_write_service.rb` | Collapse four methods to shared internal path |
| `app/services/cross_reference_updater.rb` | Generate markdown via serializer instead of reading column |
| `app/services/export_service.rb` | Generate markdown via serializer |
| `app/controllers/recipes_controller.rb` | `show_markdown`/`show_html` generate on demand |
| `app/models/recipe.rb` | Remove validation + header comment references |
| `app/views/recipes/show.html.erb` | Version hash: `updated_at` instead of `markdown_source` digest |
| `app/views/recipes/_embedded_recipe.html.erb` | Same version hash change |
| `docs/how-your-rails-app-works.md` | Update stale `markdown_source` references |
| Tests (~12 files) | Remove `markdown_source` from `Recipe.create!` calls, update assertions |

No JS changes, no new dependencies.

### Related issues

- GH #243: Collapse `AisleWriteService.sync_new_aisle`/`sync_new_aisles`
- GH #244: Extract shared `validate_order` from Aisle/CategoryWriteService
- GH #245: Parser strictness — warn or reject on unrecognized lines
