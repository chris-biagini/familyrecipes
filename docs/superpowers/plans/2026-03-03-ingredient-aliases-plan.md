# Ingredient Aliases Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Make ingredient aliases editable via the web ingredients page, and extend fuzzy matching so Inflector variants (singular/plural) are generated for alias names.

**Architecture:** Two independent changes. (1) Add an "Aliases" fieldset with tag-style chips to the nutrition editor dialog — aliases flow through the existing `assign_from_params` → save pipeline. (2) In `IngredientCatalog.add_alias_keys`, call `Inflector.ingredient_variants` on each alias to register singular/plural forms in the lookup hash.

**Tech Stack:** Rails 8, Stimulus, Turbo Streams, Minitest

---

### Task 1: Inflector variants for aliases — test

**Files:**
- Modify: `test/models/ingredient_catalog_test.rb` (after line 561, in the `# --- aliases ---` section)

**Step 1: Write the failing test**

Add two tests after the existing alias tests (around line 561):

```ruby
test 'lookup_for generates inflector variants for aliases' do
  IngredientCatalog.create!(
    ingredient_name: 'Baby spinach',
    aisle: 'Produce',
    aliases: ['Spinach']
  )

  result = IngredientCatalog.lookup_for(@kitchen)

  assert_equal result['Baby spinach'], result['Spinach']
  assert_equal result['Baby spinach'], result['Spinaches'],
               'Expected plural variant of alias to resolve'
end

test 'lookup_for inflector alias variants do not clobber canonical names' do
  IngredientCatalog.create!(
    ingredient_name: 'Egg',
    basis_grams: 50,
    aliases: ['Hen egg']
  )
  IngredientCatalog.create!(
    ingredient_name: 'Eggs',
    aisle: 'Dairy'
  )

  result = IngredientCatalog.lookup_for(@kitchen)

  assert_equal 'Eggs', result['Eggs'].ingredient_name,
               'Canonical "Eggs" must not be overwritten by inflected alias of "Egg"'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n '/inflector.*alias/'`
Expected: First test FAILS — "Spinaches" key not found in lookup. Second test should PASS (guards existing behavior).

---

### Task 2: Inflector variants for aliases — implementation

**Files:**
- Modify: `app/models/ingredient_catalog.rb:99-108` (`add_alias_keys` method)

**Step 1: Add inflector variant generation to `add_alias_keys`**

Current code at lines 99-108:
```ruby
def self.add_alias_keys(extras, entry, lookup)
  return if entry.aliases.blank?

  entry.aliases.each do |alias_name|
    lowered = alias_name.downcase
    next if lookup.key?(alias_name) || lookup.key?(lowered)

    alias_case_variants(alias_name).each { |v| extras[v] ||= entry }
  end
end
```

Replace with:
```ruby
def self.add_alias_keys(extras, entry, lookup)
  return if entry.aliases.blank?

  entry.aliases.each do |alias_name|
    lowered = alias_name.downcase
    next if lookup.key?(alias_name) || lookup.key?(lowered)

    alias_case_variants(alias_name).each { |v| extras[v] ||= entry }
    FamilyRecipes::Inflector.ingredient_variants(alias_name).each { |v| extras[v] ||= entry }
  end
end
```

One line added: `FamilyRecipes::Inflector.ingredient_variants(alias_name).each { |v| extras[v] ||= entry }`. The `||=` guard ensures inflected alias variants never clobber canonical names or previously-registered keys.

**Step 2: Run the failing tests**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n '/inflector.*alias/'`
Expected: PASS

**Step 3: Run full model test suite**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb`
Expected: All tests pass

**Step 4: Commit**

```bash
git add app/models/ingredient_catalog.rb test/models/ingredient_catalog_test.rb
git commit -m "feat: generate inflector variants for ingredient aliases

Aliases now get singular/plural forms via Inflector, so 'Spinach' as
an alias also registers 'Spinaches'. Guards prevent clobbering canonical
names. Closes the fuzzy-matching part of #157."
```

---

### Task 3: Accept aliases in assign_from_params — test

**Files:**
- Modify: `test/controllers/nutrition_entries_controller_test.rb` (add tests after existing upsert tests, around line 258)

**Step 1: Write the failing tests**

```ruby
# --- upsert with aliases ---

test 'upsert saves aliases to kitchen-scoped entry' do
  post nutrition_entry_upsert_path('Flour (all-purpose)', kitchen_slug: kitchen_slug),
       params: { nutrients: VALID_NUTRIENTS, density: nil, portions: {},
                 aisle: 'Baking', aliases: ['AP flour', 'All-purpose flour'] },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)')

  assert_equal ['AP flour', 'All-purpose flour'], entry.aliases
end

test 'upsert updates aliases on existing entry' do
  IngredientCatalog.create!(
    kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)',
    basis_grams: 30, aliases: ['AP flour']
  )

  post nutrition_entry_upsert_path('Flour (all-purpose)', kitchen_slug: kitchen_slug),
       params: { nutrients: VALID_NUTRIENTS, density: nil, portions: {},
                 aisle: nil, aliases: ['AP flour', 'Plain flour'] },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)')

  assert_equal ['AP flour', 'Plain flour'], entry.aliases
end

test 'upsert with empty aliases clears existing aliases' do
  IngredientCatalog.create!(
    kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)',
    basis_grams: 30, aliases: ['AP flour']
  )

  post nutrition_entry_upsert_path('Flour (all-purpose)', kitchen_slug: kitchen_slug),
       params: { nutrients: VALID_NUTRIENTS, density: nil, portions: {},
                 aisle: nil, aliases: [] },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)')

  assert_empty entry.aliases
end

test 'upsert without aliases key preserves existing aliases' do
  IngredientCatalog.create!(
    kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)',
    basis_grams: 30, aliases: ['AP flour']
  )

  post nutrition_entry_upsert_path('Flour (all-purpose)', kitchen_slug: kitchen_slug),
       params: { nutrients: VALID_NUTRIENTS, density: nil, portions: {}, aisle: nil },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)')

  assert_equal ['AP flour'], entry.aliases
end

test 'upsert sanitizes aliases — strips blanks, deduplicates, limits count' do
  aliases = ['AP flour', '', '  ', 'AP flour', 'Plain flour']

  post nutrition_entry_upsert_path('Flour (all-purpose)', kitchen_slug: kitchen_slug),
       params: { nutrients: VALID_NUTRIENTS, density: nil, portions: {},
                 aisle: nil, aliases: aliases },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)')

  assert_equal ['AP flour', 'Plain flour'], entry.aliases
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb -n '/alias/'`
Expected: FAIL — controller doesn't pass aliases through yet

---

### Task 4: Accept aliases in assign_from_params — implementation

**Files:**
- Modify: `app/models/ingredient_catalog.rb:54-60` (`assign_from_params`)
- Modify: `app/controllers/nutrition_entries_controller.rb:39-41` (`catalog_params`) and add `permitted_aliases`

**Step 1: Update `assign_from_params` to accept aliases**

Current (line 54-60):
```ruby
def assign_from_params(nutrients:, density:, portions:, aisle:, sources:)
  assign_nutrients(nutrients)
  assign_density(density)
  self.portions = normalize_portions_hash(portions)
  self.aisle = aisle if aisle
  self.sources = sources
end
```

Replace with:
```ruby
def assign_from_params(nutrients:, density:, portions:, aisle:, sources:, aliases: nil)
  assign_nutrients(nutrients)
  assign_density(density)
  self.portions = normalize_portions_hash(portions)
  self.aisle = aisle if aisle
  self.sources = sources
  self.aliases = aliases unless aliases.nil?
end
```

**Step 2: Update controller `catalog_params` and add `permitted_aliases`**

Current `catalog_params` (line 39-41):
```ruby
def catalog_params
  { nutrients: permitted_nutrients, density: permitted_density,
    portions: permitted_portions, aisle: params[:aisle]&.strip.presence }
end
```

Replace with:
```ruby
def catalog_params
  { nutrients: permitted_nutrients, density: permitted_density,
    portions: permitted_portions, aisle: params[:aisle]&.strip.presence,
    aliases: permitted_aliases }
end
```

Add `permitted_aliases` method after `permitted_portions` (after line 59):
```ruby
def permitted_aliases
  return unless params.key?(:aliases)

  Array(params[:aliases]).map { |a| a.to_s.strip }.reject(&:blank?).uniq.first(20)
end
```

**Step 3: Run the alias controller tests**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb -n '/alias/'`
Expected: PASS

**Step 4: Run the full controller test suite**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add app/models/ingredient_catalog.rb app/controllers/nutrition_entries_controller.rb \
        test/controllers/nutrition_entries_controller_test.rb
git commit -m "feat: accept aliases in web nutrition editor API

assign_from_params gains optional aliases: keyword. Controller sanitizes
aliases (strips blanks, deduplicates, limits to 20). Omitting the key
preserves existing aliases. Part of #157."
```

---

### Task 5: Aliases fieldset in editor form — view

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb` (add aliases fieldset between aisle section and "Used in")

**Step 1: Add the aliases fieldset**

Insert between the aisle fieldset closing `</fieldset>` (line 102) and the `<% if recipes.any? %>` block (line 104):

```erb
<fieldset class="editor-section">
  <legend class="editor-section-title">Aliases</legend>
  <p class="editor-help">
    Alternate names for this ingredient. Recipes using any alias will map
    to this entry for nutrition and grocery grouping.
  </p>
  <div class="alias-chip-list" data-nutrition-editor-target="aliasList">
    <% (entry&.aliases || []).each do |alias_name| %>
      <span class="alias-chip" data-nutrition-editor-target="aliasChip">
        <span class="alias-chip-text"><%= alias_name %></span>
        <button type="button" class="alias-chip-remove" aria-label="Remove alias"
                data-action="click->nutrition-editor#removeAlias">&times;</button>
      </span>
    <% end %>
  </div>
  <div class="alias-add-row">
    <input type="text" class="alias-input" placeholder="e.g. AP flour"
           data-nutrition-editor-target="aliasInput"
           data-action="keydown->nutrition-editor#aliasInputKeydown"
           aria-label="New alias name">
    <button type="button" class="btn add-alias"
            data-action="click->nutrition-editor#addAlias">Add</button>
  </div>
</fieldset>
```

**Step 2: Verify template renders without errors**

Start the dev server (`bin/dev`), navigate to the ingredients page, open an editor dialog. The aliases section should appear with existing aliases displayed as chips (if any exist in seed data). No JS wired yet — the "Add" button won't work until Task 6.

---

### Task 6: Aliases chip CSS

**Files:**
- Modify: `app/assets/stylesheets/style.css` (add after the `.add-portion` rule, around line 1200)

**Step 1: Add chip styles**

```css
/* Alias chips */
.alias-chip-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem;
  margin-bottom: 0.4rem;
  min-height: 1.5rem;
}

.alias-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.2rem;
  padding: 0.15rem 0.4rem;
  border-radius: 3px;
  background: var(--faint-bg);
  border: 1px solid var(--border-color);
  font-size: 0.85rem;
  line-height: 1.3;
}

.alias-chip-remove {
  appearance: none;
  -webkit-appearance: none;
  background: none;
  border: none;
  cursor: pointer;
  color: var(--muted-text);
  font-size: 1rem;
  line-height: 1;
  padding: 0 0.1rem;
}

.alias-chip-remove:hover {
  color: var(--danger-color);
}

.alias-add-row {
  display: flex;
  gap: 0.4rem;
  align-items: center;
}

.alias-input {
  flex: 1;
  font-size: 0.85rem;
  padding: 0.25rem 0.4rem;
}

.add-alias {
  font-size: 0.85rem;
}
```

**Step 2: Commit view + CSS together**

```bash
git add app/views/ingredients/_editor_form.html.erb app/assets/stylesheets/style.css
git commit -m "feat: add aliases fieldset with chip UI to editor form

Renders existing aliases as removable chips. Includes text input and
Add button for new aliases. Stimulus wiring in next commit. Part of #157."
```

---

### Task 7: Stimulus controller — alias methods

**Files:**
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`

**Step 1: Add targets**

Update the `static targets` array (line 14-21) to include the new alias targets:

```javascript
static targets = [
  "dialog", "title", "errors", "formContent",
  "saveButton", "saveNextButton", "nextLabel", "nextName",
  "basisGrams", "nutrientField",
  "densityVolume", "densityUnit", "densityGrams",
  "portionList", "portionRow", "portionName", "portionGrams",
  "aisleSelect", "aisleInput",
  "aliasList", "aliasInput", "aliasChip"
]
```

**Step 2: Add `addAlias` action method**

Add after the `removePortion` method (after line 142):

```javascript
addAlias() {
  const name = this.aliasInputTarget.value.trim()
  if (!name) return

  if (this.collectAliases().includes(name)) {
    this.aliasInputTarget.value = ""
    return
  }

  const chip = document.createElement("span")
  chip.className = "alias-chip"
  chip.setAttribute("data-nutrition-editor-target", "aliasChip")

  const text = document.createElement("span")
  text.className = "alias-chip-text"
  text.textContent = name

  const removeBtn = document.createElement("button")
  removeBtn.type = "button"
  removeBtn.className = "alias-chip-remove"
  removeBtn.setAttribute("aria-label", "Remove alias")
  removeBtn.setAttribute("data-action", "click->nutrition-editor#removeAlias")
  removeBtn.textContent = "\u00d7"

  chip.appendChild(text)
  chip.appendChild(removeBtn)
  this.aliasListTarget.appendChild(chip)
  this.aliasInputTarget.value = ""
  this.aliasInputTarget.focus()
}
```

**Step 3: Add `removeAlias` action method**

```javascript
removeAlias(event) {
  event.currentTarget.closest(".alias-chip").remove()
}
```

**Step 4: Add `aliasInputKeydown` action method**

```javascript
aliasInputKeydown(event) {
  if (event.key === "Enter") {
    event.preventDefault()
    this.addAlias()
  }
}
```

**Step 5: Add `collectAliases` helper**

```javascript
collectAliases() {
  return this.aliasChipTargets.map(chip =>
    chip.querySelector(".alias-chip-text").textContent.trim()
  )
}
```

**Step 6: Update `collectFormData` to include aliases**

Current (line 190-197):
```javascript
collectFormData() {
  return {
    nutrients: this.collectNutrients(),
    density: this.collectDensity(),
    portions: this.collectPortions(),
    aisle: this.currentAisle()
  }
}
```

Replace with:
```javascript
collectFormData() {
  return {
    nutrients: this.collectNutrients(),
    density: this.collectDensity(),
    portions: this.collectPortions(),
    aisle: this.currentAisle(),
    aliases: this.collectAliases()
  }
}
```

**Step 7: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git commit -m "feat: wire alias add/remove/collect in Stimulus controller

Adds addAlias, removeAlias, aliasInputKeydown actions and collectAliases
helper. Aliases are included in collectFormData for save and dirty
tracking. Part of #157."
```

---

### Task 8: Integration test — aliases round-trip in editor

**Files:**
- Modify: `test/controllers/ingredients_controller_test.rb` (add test at end)

**Step 1: Write integration test**

Check the `edit` action returns existing aliases in the form. Look at the existing pattern in this test file first — the edit action test checks for recipe links, so follow that pattern.

```ruby
test 'edit displays existing aliases in editor form' do
  IngredientCatalog.create!(
    kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)',
    basis_grams: 30, aliases: ['AP flour', 'Plain flour']
  )
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Test

    Category: Bread

    ## Mix (combine)

    - Flour (all-purpose), 2 cups

    Mix.
  MD

  get edit_ingredient_path('Flour (all-purpose)', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.alias-chip-text', text: 'AP flour'
  assert_select '.alias-chip-text', text: 'Plain flour'
end
```

**Step 2: Run the test**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n '/displays existing aliases/'`
Expected: PASS (the view already renders aliases from `entry.aliases`)

**Step 3: Commit**

```bash
git add test/controllers/ingredients_controller_test.rb
git commit -m "test: integration test for aliases display in editor form

Verifies the edit action renders existing aliases as chips. Part of #157."
```

---

### Task 9: Full test suite and lint

**Step 1: Run full test suite**

Run: `rake test`
Expected: All tests pass

**Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No offenses (or fix any that appear)

**Step 3: Check html_safe audit**

Run: `rake lint:html_safe`
Expected: Pass (we used `<%= alias_name %>` which auto-escapes)

**Step 4: Final commit if any fixes needed**

---

### Task 10: Manual verification

**Step 1: Start dev server**

Run: `bin/dev`

**Step 2: Navigate to ingredients page**

Open the ingredients page in the browser. Click an ingredient that has aliases in seed data (check `db/seeds/resources/ingredient-catalog.yaml` for entries with `aliases:` keys — e.g., Almonds, Baby spinach).

**Step 3: Verify aliases display**

- Existing aliases should appear as chips in the Aliases section
- Clicking `×` on a chip should remove it
- Typing a name and pressing Enter (or clicking Add) should add a new chip
- Duplicate aliases should be silently ignored
- Save should persist the aliases

**Step 4: Verify inflector matching**

Open the Rails console:
```ruby
kitchen = Kitchen.first
lookup = IngredientCatalog.lookup_for(kitchen)
# Check that a plural of an alias resolves
lookup['Spinaches']&.ingredient_name  # should return 'Baby spinach' if 'Spinach' is an alias
```
