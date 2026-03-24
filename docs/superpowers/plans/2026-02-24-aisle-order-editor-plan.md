# Aisle Order Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Let kitchen members reorder grocery aisles to match their physical store layout, with a plain-text editor on the groceries page.

**Architecture:** New `aisle_order` text column on `Kitchen`. `ShoppingListBuilder` reads the column to sort aisles by position instead of alphabetically. A new `<dialog>` on the groceries page (using the existing `editor-dialog` system) lets members edit the list. Pre-populated from distinct aisles in the kitchen's ingredient catalog.

**Tech Stack:** Rails migration, model change, service logic, controller endpoint, ERB view, existing `recipe-editor.js` dialog system.

---

### Task 1: Add `aisle_order` column to `kitchens`

**Files:**
- Create: `db/migrate/002_add_aisle_order_to_kitchens.rb`
- Modify: `db/schema.rb` (auto-generated)

**Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class AddAisleOrderToKitchens < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchens, :aisle_order, :text
  end
end
```

**Step 2: Run the migration**

Run: `rails db:migrate`
Expected: schema.rb updated with `t.text "aisle_order"` in the kitchens table.

**Step 3: Commit**

```bash
git add db/migrate/002_add_aisle_order_to_kitchens.rb db/schema.rb
git commit -m "db: add aisle_order text column to kitchens"
```

---

### Task 2: Add `Kitchen#parsed_aisle_order` helper and test

**Files:**
- Modify: `app/models/kitchen.rb`
- Create: `test/models/kitchen_aisle_order_test.rb`

**Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class KitchenAisleOrderTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test', slug: 'test')
  end

  test 'parsed_aisle_order returns empty array when nil' do
    @kitchen.update!(aisle_order: nil)

    assert_equal [], @kitchen.parsed_aisle_order
  end

  test 'parsed_aisle_order splits lines and strips whitespace' do
    @kitchen.update!(aisle_order: "Produce\n  Baking \nFrozen\n")

    assert_equal %w[Produce Baking Frozen], @kitchen.parsed_aisle_order
  end

  test 'parsed_aisle_order skips blank lines' do
    @kitchen.update!(aisle_order: "Produce\n\n\nBaking\n")

    assert_equal %w[Produce Baking], @kitchen.parsed_aisle_order
  end

  test 'normalize_aisle_order! deduplicates and strips' do
    @kitchen.aisle_order = "Produce\nBaking\n  Produce \nFrozen"
    @kitchen.normalize_aisle_order!

    assert_equal "Produce\nBaking\nFrozen", @kitchen.aisle_order
  end

  test 'normalize_aisle_order! sets nil for empty input' do
    @kitchen.aisle_order = "  \n  \n"
    @kitchen.normalize_aisle_order!

    assert_nil @kitchen.aisle_order
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/kitchen_aisle_order_test.rb`
Expected: FAIL — `parsed_aisle_order` and `normalize_aisle_order!` not defined.

**Step 3: Implement the methods on Kitchen**

Add to `app/models/kitchen.rb`:

```ruby
def parsed_aisle_order
  return [] unless aisle_order

  aisle_order.lines.map(&:strip).reject(&:empty?)
end

def normalize_aisle_order!
  lines = parsed_aisle_order.uniq
  self.aisle_order = lines.empty? ? nil : lines.join("\n")
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/kitchen_aisle_order_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/models/kitchen.rb test/models/kitchen_aisle_order_test.rb
git commit -m "feat: add parsed_aisle_order and normalize helpers to Kitchen"
```

---

### Task 3: Update `ShoppingListBuilder` to use aisle order

**Files:**
- Modify: `app/services/shopping_list_builder.rb:92-104` (the `organize_by_aisle` method)
- Modify: `test/services/shopping_list_builder_test.rb`

**Step 1: Write the failing tests**

Add to `test/services/shopping_list_builder_test.rb`:

```ruby
test 'respects kitchen aisle_order for sorting' do
  @kitchen.update!(aisle_order: "Spices\nBaking")
  list = GroceryList.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
  aisle_names = result.keys

  assert_equal 'Spices', aisle_names[0]
  assert_equal 'Baking', aisle_names[1]
end

test 'unordered aisles appear after ordered aisles alphabetically' do
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Eggs') do |p|
    p.basis_grams = 50
    p.aisle = 'Refrigerated'
  end

  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Scramble

    Category: Bread

    ## Cook (scramble)

    - Eggs, 3
    - Flour, 1 cup
    - Salt, 1 tsp

    Cook.
  MD

  @kitchen.update!(aisle_order: "Spices\nBaking")
  list = GroceryList.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'scramble', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
  aisle_names = result.keys

  assert_equal %w[Spices Baking Refrigerated], aisle_names
end

test 'Miscellaneous sorts last even with aisle_order' do
  IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)
  @kitchen.update!(aisle_order: "Baking")

  list = GroceryList.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

  assert_equal 'Miscellaneous', result.keys.last
end

test 'Miscellaneous respects explicit position in aisle_order' do
  IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)
  @kitchen.update!(aisle_order: "Miscellaneous\nBaking")

  list = GroceryList.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

  assert_equal %w[Miscellaneous Baking], result.keys
end

test 'falls back to alphabetical when aisle_order is nil' do
  @kitchen.update!(aisle_order: nil)
  list = GroceryList.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
  aisle_names = result.keys

  assert_equal %w[Baking Spices], aisle_names
end
```

**Step 2: Run tests to verify the new ones fail**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: New order-related tests fail (current sort is alphabetical).

**Step 3: Implement the new sorting logic**

Replace the `organize_by_aisle` method in `app/services/shopping_list_builder.rb`:

```ruby
def organize_by_aisle(ingredients)
  result = Hash.new { |h, k| h[k] = [] }

  ingredients.each do |name, amounts|
    aisle = @profiles[name]&.aisle
    next if aisle == 'omit'

    target_aisle = aisle || 'Miscellaneous'
    result[target_aisle] << { name: name, amounts: serialize_amounts(amounts) }
  end

  sort_aisles(result)
end

def sort_aisles(aisles_hash)
  order = @kitchen.parsed_aisle_order
  return aisles_hash.sort_by { |aisle, _| aisle == 'Miscellaneous' ? 'zzz' : aisle }.to_h if order.empty?

  aisles_hash.sort_by { |aisle, _| aisle_sort_key(aisle, order) }.to_h
end

def aisle_sort_key(aisle, order)
  position = order.index(aisle)
  return [0, position] if position

  # Miscellaneous defaults to last unless explicitly ordered
  return [2, 0] if aisle == 'Miscellaneous'

  # Unordered aisles sort alphabetically after ordered ones
  [1, aisle]
end
```

Note: the sort key is a two-element array. Ordered aisles get `[0, index]`, unordered get `[1, name]`, and Miscellaneous (when not explicitly placed) gets `[2, 0]`. Ruby's array comparison sorts these correctly.

**Step 4: Run all tests to verify they pass**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: All pass (old and new).

**Step 5: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "feat: ShoppingListBuilder sorts aisles by kitchen aisle_order"
```

---

### Task 4: Add controller endpoint and route

**Files:**
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `config/routes.rb`
- Modify: `test/controllers/groceries_controller_test.rb`

**Step 1: Write the failing tests**

Add to `test/controllers/groceries_controller_test.rb`:

```ruby
# --- Aisle order ---

test 'update_aisle_order requires membership' do
  patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
        params: { aisle_order: "Produce\nBaking" },
        as: :json

  assert_response :unauthorized
end

test 'update_aisle_order saves valid order' do
  log_in
  patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
        params: { aisle_order: "Produce\n  Baking\nProduce\n\nFrozen" },
        as: :json

  assert_response :success
  assert_equal "Produce\nBaking\nFrozen", @kitchen.reload.aisle_order
end

test 'update_aisle_order clears order when empty' do
  @kitchen.update!(aisle_order: "Produce\nBaking")

  log_in
  patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
        params: { aisle_order: '' },
        as: :json

  assert_response :success
  assert_nil @kitchen.reload.aisle_order
end

test 'aisle_order_content returns current aisles for editor' do
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
    p.basis_grams = 6
    p.aisle = 'Spices'
  end

  log_in
  get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :success
  json = JSON.parse(response.body)

  assert_includes json['aisle_order'], 'Baking'
  assert_includes json['aisle_order'], 'Spices'
end

test 'aisle_order_content merges saved order with catalog aisles' do
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
    p.basis_grams = 6
    p.aisle = 'Spices'
  end

  @kitchen.update!(aisle_order: "Spices\nProduce")

  log_in
  get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :json

  json = JSON.parse(response.body)
  lines = json['aisle_order'].lines.map(&:strip)

  # Saved order preserved, new aisle appended
  assert_equal 'Spices', lines[0]
  assert_equal 'Produce', lines[1]
  assert_includes lines, 'Baking'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: FAIL — route and action not defined.

**Step 3: Add the route**

Add to `config/routes.rb` inside the `scope 'kitchens/:kitchen_slug'` block, after the `groceries/quick_bites` line:

```ruby
patch 'groceries/aisle_order', to: 'groceries#update_aisle_order', as: :groceries_aisle_order
get 'groceries/aisle_order_content', to: 'groceries#aisle_order_content', as: :groceries_aisle_order_content
```

**Step 4: Add the controller actions**

Add to `app/controllers/groceries_controller.rb`, after the `update_quick_bites` method:

```ruby
def update_aisle_order
  current_kitchen.aisle_order = params[:aisle_order].to_s
  current_kitchen.normalize_aisle_order!
  current_kitchen.save!

  GroceryListChannel.broadcast_content_changed(current_kitchen)
  render json: { status: 'ok' }
end

def aisle_order_content
  render json: { aisle_order: build_aisle_order_text }
end
```

Add to the `private` section:

```ruby
def build_aisle_order_text
  saved = current_kitchen.parsed_aisle_order
  catalog_aisles = IngredientCatalog.lookup_for(current_kitchen)
                     .values
                     .filter_map(&:aisle)
                     .uniq
                     .reject { |a| a == 'omit' }
                     .sort

  new_aisles = catalog_aisles - saved
  (saved + new_aisles).join("\n")
end
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass.

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/groceries_controller.rb test/controllers/groceries_controller_test.rb
git commit -m "feat: add aisle order PATCH endpoint and content loader"
```

---

### Task 5: Add the editor dialog to the groceries view

**Files:**
- Modify: `app/views/groceries/show.html.erb`

**Step 1: Add the "Aisle Order" button to `extra_nav`**

In `app/views/groceries/show.html.erb`, update the `content_for(:extra_nav)` block. Currently it contains a single "Edit Quick Bites" button. Add the aisle order button next to it:

```erb
<% content_for(:extra_nav) do %>
  <div>
    <button type="button" id="edit-aisle-order-button" class="btn">Aisle Order</button>
    <button type="button" id="edit-quick-bites-button" class="btn">Edit Quick Bites</button>
  </div>
<% end %>
```

**Step 2: Add the editor dialog**

Add a second `<dialog>` block after the existing Quick Bites dialog, inside the `current_kitchen.member?(current_user)` guard:

```erb
<dialog class="editor-dialog"
        data-editor-open="#edit-aisle-order-button"
        data-editor-url="<%= groceries_aisle_order_path %>"
        data-editor-method="PATCH"
        data-editor-on-success="reload"
        data-editor-body-key="aisle_order"
        data-editor-load-url="<%= groceries_aisle_order_content_path %>"
        data-editor-load-key="aisle_order">
  <div class="editor-header">
    <h2>Aisle Order</h2>
    <button type="button" class="btn editor-close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" hidden></div>
  <textarea class="editor-textarea" spellcheck="false" placeholder="Loading..."></textarea>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary editor-save">Save</button>
  </div>
</dialog>
```

Note: the `data-editor-load-url` and `data-editor-load-key` attributes are new — they tell `recipe-editor.js` to fetch content on open rather than using the static textarea content. This is necessary because the aisle list is computed dynamically (merging saved order with catalog aisles). **This requires a small JS change in Task 6.**

**Step 3: Verify the page renders**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n test_renders_the_groceries_page_with_recipe_checkboxes`
Expected: Pass. Then manually verify by starting `bin/dev` and checking the groceries page.

**Step 4: Commit**

```bash
git add app/views/groceries/show.html.erb
git commit -m "feat: add aisle order editor dialog to groceries page"
```

---

### Task 6: Add dynamic content loading to `recipe-editor.js`

**Files:**
- Modify: `app/assets/javascripts/recipe-editor.js`
- Test: manual browser test (JS is not unit tested in this project)

The existing `recipe-editor.js` system reads textarea content statically from the HTML. The aisle order editor needs to fetch content from an API endpoint when the dialog opens, because the content is computed dynamically (saved order + new aisles from catalog).

**Step 1: Read the current `recipe-editor.js`** to understand the dialog setup flow.

**Step 2: Add dynamic loading support**

In `recipe-editor.js`, find the code that runs when the open button is clicked (the dialog `.showModal()` call). Before showing the modal, check for `data-editor-load-url`. If present, fetch the content and populate the textarea:

```javascript
// In the open handler, before dialog.showModal():
var loadUrl = dialog.dataset.editorLoadUrl;
if (loadUrl) {
  var textarea = dialog.querySelector('.editor-textarea');
  textarea.value = 'Loading...';
  textarea.disabled = true;
  dialog.showModal();

  fetch(loadUrl, {
    headers: { 'Accept': 'application/json', 'X-CSRF-Token': getCSRFToken() }
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      var key = dialog.dataset.editorLoadKey || 'content';
      textarea.value = data[key] || '';
      textarea.disabled = false;
      textarea.focus();
    })
    .catch(function() {
      textarea.value = 'Failed to load content. Close and try again.';
    });
} else {
  dialog.showModal();
}
```

The exact integration point depends on the current structure of `recipe-editor.js`. Read it first, then integrate this logic into the existing open handler.

**Step 3: Test manually**

1. Start `bin/dev`
2. Log in, go to groceries page
3. Click "Aisle Order" button
4. Verify textarea loads with aisle names from the catalog
5. Reorder some lines, click Save
6. Reopen — verify the new order is preserved with any new aisles appended

**Step 4: Commit**

```bash
git add app/assets/javascripts/recipe-editor.js
git commit -m "feat: support dynamic content loading in editor dialogs"
```

---

### Task 7: Add controller test for the editor dialog rendering

**Files:**
- Modify: `test/controllers/groceries_controller_test.rb`

**Step 1: Write the test**

```ruby
test 'renders aisle order editor dialog for members' do
  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '#edit-aisle-order-button', 'Aisle Order'
  assert_select 'dialog[data-editor-open="#edit-aisle-order-button"]'
end
```

**Step 2: Run it**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n test_renders_aisle_order_editor_dialog_for_members`
Expected: Pass.

**Step 3: Run the full test suite**

Run: `rake test`
Expected: All pass.

**Step 4: Run lint**

Run: `rake lint`
Expected: Clean.

**Step 5: Commit**

```bash
git add test/controllers/groceries_controller_test.rb
git commit -m "test: add aisle order editor dialog rendering test"
```

---

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

Update the Routes section to mention the new aisle order endpoints. Update the Kitchen model description to mention `aisle_order`. Keep changes minimal.

**Step 1: Add to the Routes section**

After the groceries routes list, add the aisle order routes.

**Step 2: Add to the Kitchen model description**

Add `aisle_order` text column mention to the Kitchen bullet.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with aisle order feature"
```
