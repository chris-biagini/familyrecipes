# Deferred Cross-Reference Resolution

**Issue:** [#91](https://github.com/chris-biagini/familyrecipes/issues/91)
**Date:** 2026-02-24

## Problem

`MarkdownImporter#import_cross_reference` silently drops cross-references when the target recipe doesn't exist yet. During `db:seed`, recipes are imported in filesystem glob order -- if Recipe A references Recipe B and B hasn't been imported yet, the cross-reference is lost with no warning.

This affects both the seed path (batch import) and the web editor path (single-recipe save could reference a recipe that was just deleted or hasn't been created yet).

## Design

### Approach: Deferred Cross-References

Always persist cross-references at import time, even when the target recipe doesn't exist yet. Resolve the FK later when the target becomes available.

### Schema Change

Add two columns to `cross_references`, make `target_recipe_id` nullable:

```
target_slug   string  NOT NULL  -- slug of the referenced recipe (always populated)
target_title  string  NOT NULL  -- display title (always populated)
target_recipe_id      nullable  -- resolved FK (NULL until target exists)
```

`target_slug` and `target_title` are set from parsed data at import time. They serve as the durable identity for unresolved references and as display values in views.

### CrossReference Model

- `belongs_to :target_recipe, optional: true`
- Remove existing delegates (column accessors replace them)
- Add `scope :pending` (where target_recipe_id is nil)
- Add `scope :resolved` (where target_recipe_id is not nil)
- Add `resolved?` / `pending?` predicates
- Add `self.resolve_pending(kitchen:)` class method: finds all pending refs in the kitchen and links them to matching recipes by slug

### MarkdownImporter

- `import_cross_reference`: always create the CrossReference with target_slug and target_title. Set target_recipe if found, leave nil if not. No more `return unless target`.
- After saving a recipe, call `CrossReference.resolve_pending(kitchen:)` to pick up any refs that were waiting for this recipe.

### Seeds

- After the recipe import loop, call `CrossReference.resolve_pending(kitchen:)` as a safety net.
- Log a warning if any unresolved references remain after the full import.

### View Rendering

- Resolved cross-references render as links (existing behavior).
- Pending cross-references render as plain text showing the target title. No broken links.
- The step partial checks `resolved?` before generating a link.

### CrossReferenceUpdater

No changes needed. It already operates on existing CrossReference records and updates slugs/titles when recipes are renamed. The new columns give it a natural place to update stored titles.

## Testing

- **Model:** `resolve_pending` resolves refs when target exists, skips when it doesn't. `resolved?`/`pending?` predicates.
- **MarkdownImporter:** Import recipe with cross-reference to nonexistent target -- ref is created as pending. Import the target -- ref resolves.
- **Seeds:** No unresolved refs after full seed run.
- **View:** Pending refs render as plain text, resolved refs render as links.
