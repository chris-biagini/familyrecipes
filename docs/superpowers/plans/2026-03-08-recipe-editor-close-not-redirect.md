# Recipe Editor: Close Instead of Redirect

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the recipe editor's post-save redirect with dialog close + Turbo morph, eliminating a redundant full page navigation.

**Architecture:** The recipe editor currently does `window.location = redirectUrl` after a successful PATCH, but `RecipeWriteService` already calls `Kitchen#broadcast_update` which triggers a Turbo morph on all connected clients. The redirect is redundant. The editor should close the dialog and let morph handle the page refresh. For renames (slug changes), `history.replaceState` updates the URL without navigation. The `updated_references` notification moves from a query-param-on-redirect to a direct toast after save.

**Tech Stack:** Rails controller, Stimulus (editor_controller.js), Turbo morph

---

### Task 1: Update controller tests for new response format

**Files:**
- Modify: `test/controllers/recipes_controller_test.rb:137,189`

**Step 1: Change update test assertions from `redirect_url` to `slug`**

The two update tests that assert `redirect_url` should assert `slug` instead:

```ruby
# Line 137 — update test (no rename)
assert_equal 'focaccia', body['slug']

# Line 189 — update with rename test
assert_equal 'rosemary-focaccia', body['slug']
```

The `updated_references` test (line 249) needs no change — it already asserts on `body['updated_references']`.

Create and destroy tests keep their `redirect_url` assertions unchanged.

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /update/`
Expected: 2 failures (assertions expect `slug` but controller still returns `redirect_url`)

---

### Task 2: Update controller response format

**Files:**
- Modify: `app/controllers/recipes_controller.rb:55-58`

**Step 1: Simplify the update response**

Replace the `update_response` method:

```ruby
def update_response(result)
  response = { slug: result.recipe.slug }
  response[:updated_references] = result.updated_references if result.updated_references.any?
  response
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: all pass

**Step 3: Commit**

```
fix: return slug instead of redirect_url from recipe update endpoint
```

---

### Task 3: Add close-with-slug handling to editor_controller.js

**Files:**
- Modify: `app/javascript/controllers/editor_controller.js:82-108`

**Step 1: Update the save success callback**

In the `save()` method, the `onSuccessValue === "close"` branch currently just closes the dialog. It needs to also handle slug changes and updated_references notifications. Update the close branch:

```javascript
} else if (this.onSuccessValue === "close") {
  if (responseData.slug) {
    const currentSlug = window.location.pathname.split("/").pop()
    if (responseData.slug !== currentSlug) {
      const newPath = window.location.pathname.replace(currentSlug, responseData.slug)
      history.replaceState(null, "", newPath)
    }
  }
  if (responseData.updated_references?.length > 0) {
    notifyShow(`Updated references in ${responseData.updated_references.join(", ")}.`)
  }
  this.element.close()
}
```

**Step 2: Verify manually** — no JS test infrastructure, but controller tests cover the response format.

---

### Task 4: Switch recipe edit view to onSuccess: 'close'

**Files:**
- Modify: `app/views/recipes/show.html.erb:46`

**Step 1: Change the editor_on_success value**

```erb
editor_on_success: 'close',
```

This is a one-line change. The "New Recipe" editor on the homepage keeps `redirect` (it needs to navigate to the new recipe's URL).

**Step 2: Run full test suite**

Run: `rake test`
Expected: all pass

**Step 3: Commit**

```
feat: recipe editor closes instead of redirecting after save

Turbo morph (via Kitchen#broadcast_update) already refreshes the page
after a save. The redirect was redundant overhead — a full page
navigation that morph handles automatically. For renames (slug changes),
history.replaceState updates the URL without navigation.

Closes #202
```

---

### Task 5: Remove dead code (checkRefsUpdated)

**Files:**
- Modify: `app/javascript/controllers/editor_controller.js`

**Step 1: Assess whether checkRefsUpdated is still reachable**

`checkRefsUpdated` reads a `refs_updated` query param from the URL. This param was only appended by the redirect path in the `save()` method (lines 101-105). After Task 3:

- Recipe **update** now uses `close` — shows notification directly, no query param.
- Recipe **create** still uses `redirect` — but `create` never returns `updated_references` (new recipes can't have cross-references yet).
- Recipe **delete** uses `redirect` — but `destroy` never returns `updated_references`.

So the `refs_updated` query param building (lines 101-105 in the redirect branch) and `checkRefsUpdated()` (lines 246-254) are both dead code.

**Step 2: Remove `checkRefsUpdated` method and its call**

Remove from `connect()`:
```javascript
this.checkRefsUpdated()
```

Remove the entire `checkRefsUpdated()` method (lines 246-254).

Remove the `updated_references` handling from the redirect branch (lines 101-105), since no redirect path produces this data anymore.

Remove the `notify` import if nothing else uses it — check first. (The close branch in Task 3 now uses `notifyShow`, so the import stays.)

**Step 3: Run lint and tests**

Run: `rake`
Expected: all pass

**Step 4: Commit**

```
chore: remove dead checkRefsUpdated code from editor controller
```
