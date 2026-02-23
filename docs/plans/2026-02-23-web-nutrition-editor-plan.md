# Web Nutrition Editor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a web-based nutrition data editor to the ingredients page, with an overlay data model (global seed data + per-kitchen overrides) and a plaintext nutrition label dialog.

**Architecture:** NutritionEntry gets nullable kitchen_id (NULL = global seed data, non-NULL = kitchen override). A new NutritionLabelParser service parses plaintext nutrition labels. NutritionEntriesController handles upsert/destroy with copy-on-write semantics. The ingredients page is redesigned with nutrition status badges and an editor dialog.

**Tech Stack:** Rails 8, PostgreSQL, Minitest, existing editor-dialog JS pattern (no new JS files)

**Design doc:** `docs/plans/2026-02-23-web-nutrition-editor-design.md`

---

### Task 0: Create feature branch and worktree

**Step 1: Create worktree**

Use the `using-git-worktrees` skill to create an isolated worktree for this feature.

Branch name: `web-nutrition-editor`

---

### Task 1: Migration — make kitchen_id nullable on nutrition_entries

**Files:**
- Create: `db/migrate/TIMESTAMP_make_nutrition_entry_kitchen_optional.rb`

**Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class MakeNutritionEntryKitchenOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :nutrition_entries, :kitchen_id, true

    add_index :nutrition_entries, :ingredient_name,
              unique: true,
              where: 'kitchen_id IS NULL',
              name: 'index_nutrition_entries_global_unique'
  end
end
```

**Step 2: Run migration**

Run: `rails db:migrate`
Expected: Migration succeeds, `db/schema.rb` updated with nullable `kitchen_id` and new partial index.

**Step 3: Verify schema**

Check `db/schema.rb` shows `null: false` removed from `kitchen_id` and the new index present.

**Step 4: Commit**

```bash
git add db/migrate/*make_nutrition_entry_kitchen_optional* db/schema.rb
git commit -m "feat: make nutrition_entries.kitchen_id nullable for global entries"
```

---

### Task 2: Update NutritionEntry model — remove acts_as_tenant, add overlay logic

**Files:**
- Modify: `app/models/nutrition_entry.rb`
- Create: `test/models/nutrition_entry_test.rb`

**Step 1: Write tests for the overlay model**

```ruby
# frozen_string_literal: true

require 'test_helper'

class NutritionEntryTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    NutritionEntry.where(kitchen_id: [@kitchen.id, nil]).delete_all
  end

  test 'global? returns true when kitchen_id is nil' do
    entry = NutritionEntry.create!(ingredient_name: 'Butter', basis_grams: 100)
    assert_predicate entry, :global?
    refute_predicate entry, :custom?
  end

  test 'custom? returns true when kitchen_id is present' do
    entry = NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)
    refute_predicate entry, :global?
    assert_predicate entry, :custom?
  end

  test 'lookup_for returns global entries when no kitchen overrides' do
    NutritionEntry.create!(ingredient_name: 'Butter', basis_grams: 100, calories: 717)
    result = NutritionEntry.lookup_for(@kitchen)

    assert_equal 1, result.size
    assert_equal 717, result['Butter'].calories.to_f
    assert_predicate result['Butter'], :global?
  end

  test 'lookup_for returns kitchen override when it exists' do
    NutritionEntry.create!(ingredient_name: 'Butter', basis_grams: 100, calories: 717)
    NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100, calories: 700)

    result = NutritionEntry.lookup_for(@kitchen)

    assert_equal 1, result.size
    assert_equal 700, result['Butter'].calories.to_f
    assert_predicate result['Butter'], :custom?
  end

  test 'lookup_for merges global and kitchen entries' do
    NutritionEntry.create!(ingredient_name: 'Butter', basis_grams: 100)
    NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30)

    result = NutritionEntry.lookup_for(@kitchen)

    assert_equal 2, result.size
    assert result.key?('Butter')
    assert result.key?('Flour')
  end

  test 'lookup_for does not return entries from other kitchens' do
    other = Kitchen.find_or_create_by!(name: 'Other Kitchen', slug: 'other-kitchen')
    NutritionEntry.create!(kitchen: other, ingredient_name: 'Butter', basis_grams: 100)

    result = NutritionEntry.lookup_for(@kitchen)

    assert_empty result
  end

  test 'validates ingredient_name presence' do
    entry = NutritionEntry.new(basis_grams: 100)

    refute_predicate entry, :valid?
    assert_includes entry.errors[:ingredient_name], "can't be blank"
  end

  test 'validates basis_grams greater than zero' do
    entry = NutritionEntry.new(ingredient_name: 'Test', basis_grams: 0)

    refute_predicate entry, :valid?
  end

  test 'enforces uniqueness of ingredient_name within same kitchen' do
    NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)

    duplicate = NutritionEntry.new(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)
    refute_predicate duplicate, :valid?
  end

  test 'allows same ingredient_name in different kitchens' do
    other = Kitchen.find_or_create_by!(name: 'Other Kitchen', slug: 'other-kitchen')
    NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)

    entry = NutritionEntry.new(kitchen: other, ingredient_name: 'Butter', basis_grams: 100)
    assert_predicate entry, :valid?
  end

  test 'allows same ingredient_name as global and kitchen entry' do
    NutritionEntry.create!(ingredient_name: 'Butter', basis_grams: 100)

    entry = NutritionEntry.new(kitchen: @kitchen, ingredient_name: 'Butter', basis_grams: 100)
    assert_predicate entry, :valid?
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/models/nutrition_entry_test.rb`
Expected: Failures because `global?`, `custom?`, `lookup_for` don't exist yet.

**Step 3: Implement the model**

Replace `app/models/nutrition_entry.rb`:

```ruby
# frozen_string_literal: true

class NutritionEntry < ApplicationRecord
  belongs_to :kitchen, optional: true

  validates :ingredient_name, presence: true
  validates :ingredient_name, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, presence: true, numericality: { greater_than: 0 }

  scope :global, -> { where(kitchen_id: nil) }
  scope :for_kitchen, ->(kitchen) { where(kitchen_id: kitchen.id) }

  def global? = kitchen_id.nil?
  def custom? = kitchen_id.present?

  def self.lookup_for(kitchen)
    global.index_by(&:ingredient_name)
          .merge(for_kitchen(kitchen).index_by(&:ingredient_name))
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `rake test TEST=test/models/nutrition_entry_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/models/nutrition_entry.rb test/models/nutrition_entry_test.rb
git commit -m "feat: NutritionEntry overlay model with global + kitchen scoping"
```

---

### Task 3: Update db/seeds.rb — seed global entries (NULL kitchen_id)

**Files:**
- Modify: `db/seeds.rb` (lines 83-123)

**Step 1: Update the nutrition seeding block**

Replace the nutrition seeding section (lines 83-123) in `db/seeds.rb`. The key changes:
- `NutritionEntry` rows are created without a kitchen (`kitchen_id: nil` — global entries)
- Use `find_or_initialize_by(kitchen_id: nil, ingredient_name: name)` instead of just `ingredient_name`
- Remove the `ActsAsTenant.current_tenant` dependency for these rows
- The `SiteDocument` for `nutrition_data` remains kitchen-scoped (it's a display artifact)

```ruby
# Seed Nutrition Data document and NutritionEntry rows
nutrition_path = resources_dir.join('nutrition-data.yaml')
if File.exist?(nutrition_path)
  raw_content = File.read(nutrition_path)

  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'nutrition_data') do |doc|
    doc.content = raw_content
  end
  puts 'Nutrition Data document loaded.'

  nutrition_data = YAML.safe_load(raw_content, permitted_classes: [], permitted_symbols: [], aliases: false)
  nutrition_data.each do |name, entry|
    nutrients = entry['nutrients']
    next unless nutrients.is_a?(Hash) && nutrients['basis_grams'].is_a?(Numeric)

    density = entry['density'] || {}
    NutritionEntry.find_or_initialize_by(kitchen_id: nil, ingredient_name: name).tap do |ne|
      ne.assign_attributes(
        basis_grams: nutrients['basis_grams'],
        calories: nutrients['calories'],
        fat: nutrients['fat'],
        saturated_fat: nutrients['saturated_fat'],
        trans_fat: nutrients['trans_fat'],
        cholesterol: nutrients['cholesterol'],
        sodium: nutrients['sodium'],
        carbs: nutrients['carbs'],
        fiber: nutrients['fiber'],
        total_sugars: nutrients['total_sugars'],
        added_sugars: nutrients['added_sugars'],
        protein: nutrients['protein'],
        density_grams: density['grams'],
        density_volume: density['volume'],
        density_unit: density['unit'],
        portions: entry['portions'] || {},
        sources: entry['sources'] || []
      )
      ne.save!
    end
  end
  puts "Seeded #{NutritionEntry.global.count} global nutrition entries."
end
```

**Step 2: Run seed to verify**

Run: `rails db:seed`
Expected: Seeds run successfully. Nutrition entries are global (kitchen_id = NULL).

**Step 3: Verify in console**

Run: `rails runner "puts NutritionEntry.global.count; puts NutritionEntry.where.not(kitchen_id: nil).count"`
Expected: Global count matches number of ingredients in YAML. Kitchen-scoped count may have old entries from previous seeds.

**Step 4: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: seed nutrition entries as global (kitchen_id NULL)"
```

---

### Task 4: Update RecipeNutritionJob — use lookup_for overlay

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb`
- Modify: `test/jobs/recipe_nutrition_job_test.rb`

**Step 1: Write a test for overlay behavior**

Add to `test/jobs/recipe_nutrition_job_test.rb`:

```ruby
test 'uses kitchen override when available' do
  # Global entry exists from setup (Flour, calories: 110)
  # Create kitchen override with different calories
  NutritionEntry.create!(
    kitchen: @kitchen,
    ingredient_name: 'Flour',
    basis_grams: 30.0,
    calories: 200.0,
    fat: 1.0,
    protein: 5.0
  )

  markdown = "# Bread\n\nCategory: Cat\nServes: 1\n\n## Mix\n\n- Flour, 30 g\n\nMix."
  recipe = import_without_nutrition(markdown)

  RecipeNutritionJob.perform_now(recipe)
  recipe.reload

  # Should use the kitchen override (200 cal) not global (110 cal)
  assert_equal 200.0, recipe.nutrition_data['totals']['calories']
end
```

**Step 2: Run new test to verify it fails**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb -n test_uses_kitchen_override_when_available`
Expected: Fails because job still uses `NutritionEntry.all` with acts_as_tenant.

**Step 3: Update the job**

In `app/jobs/recipe_nutrition_job.rb`, change `build_nutrition_lookup` to use the overlay and remove the `ActsAsTenant.with_tenant` wrapper:

Replace the `perform` method:
```ruby
def perform(recipe)
  nutrition_data = build_nutrition_lookup(recipe.kitchen)
  return if nutrition_data.empty?

  calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: omit_set)
  result = calculator.calculate(parsed_recipe(recipe), alias_map, recipe_map(recipe.kitchen))

  recipe.update_column(:nutrition_data, serialize_result(result))
end
```

Replace `build_nutrition_lookup`:
```ruby
def build_nutrition_lookup(kitchen)
  NutritionEntry.lookup_for(kitchen).transform_values do |entry|
    data = { 'nutrients' => nutrients_hash(entry) }
    data['density'] = density_hash(entry) if entry.density_grams && entry.density_volume && entry.density_unit
    data['portions'] = entry.portions if entry.portions.present?
    data
  end
end
```

Also update `recipe_map` to accept a kitchen parameter instead of using the tenant scope:
```ruby
def recipe_map(kitchen)
  @recipe_map ||= kitchen.recipes.includes(:category).to_h do |r|
    [r.slug, parsed_recipe(r)]
  end
end
```

**Step 4: Update existing tests**

The existing tests create `NutritionEntry` with `acts_as_tenant` (implicitly uses `@kitchen`). Since we removed `acts_as_tenant`, these entries are now kitchen-scoped explicitly. Update the `setup` block:

In `test/jobs/recipe_nutrition_job_test.rb`, change the `setup` `NutritionEntry.create!` call to explicitly pass `kitchen: nil` if we want them as global entries, or `kitchen: @kitchen` for kitchen-scoped. Since the existing tests use `ActsAsTenant.current_tenant = @kitchen`, the `NutritionEntry.create!` in setup already creates kitchen-scoped entries. But with `acts_as_tenant` removed, we need to be explicit.

Change the setup's NutritionEntry creation to be global (matching how seed data works):

```ruby
NutritionEntry.create!(
  ingredient_name: 'Flour',
  basis_grams: 30.0,
  calories: 110.0,
  fat: 0.5,
  protein: 3.0
)
```

This creates a global entry (kitchen_id nil). The `NutritionEntry.destroy_all` in setup also needs to handle both global and kitchen-scoped. Since `acts_as_tenant` is removed, `NutritionEntry.destroy_all` already destroys all entries.

**Step 5: Run all nutrition job tests**

Run: `rake test TEST=test/jobs/recipe_nutrition_job_test.rb`
Expected: All pass, including the new overlay test.

**Step 6: Commit**

```bash
git add app/jobs/recipe_nutrition_job.rb test/jobs/recipe_nutrition_job_test.rb
git commit -m "feat: RecipeNutritionJob uses overlay lookup_for instead of tenant scope"
```

---

### Task 5: NutritionLabelParser — parse plaintext nutrition labels

**Files:**
- Create: `app/services/nutrition_label_parser.rb`
- Create: `test/services/nutrition_label_parser_test.rb`

**Step 1: Write comprehensive parser tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class NutritionLabelParserTest < ActiveSupport::TestCase
  test 'parses a complete label with density' do
    text = <<~LABEL
      Serving size: 1/4 cup (30g)

      Calories          110
      Total Fat         0.5g
        Saturated Fat   0g
        Trans Fat       0g
      Cholesterol       0mg
      Sodium            0mg
      Total Carbs       23g
        Dietary Fiber   1g
        Total Sugars    0g
          Added Sugars  0g
      Protein           3g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 30.0, result.nutrients[:basis_grams]
    assert_equal 110.0, result.nutrients[:calories]
    assert_equal 0.5, result.nutrients[:fat]
    assert_equal 23.0, result.nutrients[:carbs]
    assert_equal 3.0, result.nutrients[:protein]

    assert_equal 30.0, result.density[:grams]
    assert_equal 0.25, result.density[:volume]
    assert_equal 'cup', result.density[:unit]
  end

  test 'parses label with gram-only serving size' do
    text = <<~LABEL
      Serving size: 30g

      Calories          110
      Total Fat         0g
      Protein           3g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 30.0, result.nutrients[:basis_grams]
    assert_nil result.density
  end

  test 'parses label with portions section' do
    text = <<~LABEL
      Serving size: 100g

      Calories          717

      Portions:
        stick: 113g
        pat: 5g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 113.0, result.portions['stick']
    assert_equal 5.0, result.portions['pat']
  end

  test 'parses ~unitless portion' do
    text = <<~LABEL
      Serving size: 50g

      Calories          72

      Portions:
        ~unitless: 50g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 50.0, result.portions['~unitless']
  end

  test 'missing lines default to zero' do
    text = <<~LABEL
      Serving size: 30g

      Calories          100
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 0, result.nutrients[:fat]
    assert_equal 0, result.nutrients[:sodium]
    assert_equal 0, result.nutrients[:protein]
  end

  test 'fails when serving size is missing' do
    text = <<~LABEL
      Calories          100
      Total Fat         5g
    LABEL

    result = NutritionLabelParser.parse(text)

    refute_predicate result, :success?
    assert_includes result.errors, 'Serving size is required (e.g., "Serving size: 30g" or "Serving size: 1/4 cup (30g)")'
  end

  test 'fails when serving size has no gram weight' do
    text = <<~LABEL
      Serving size: 1/4 cup

      Calories          100
    LABEL

    result = NutritionLabelParser.parse(text)

    refute_predicate result, :success?
    assert result.errors.any? { |e| e.include?('gram weight') }
  end

  test 'handles unit suffixes case-insensitively' do
    text = <<~LABEL
      Serving size: 30G

      calories          100
      total fat         5G
      PROTEIN           3G
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 100.0, result.nutrients[:calories]
    assert_equal 5.0, result.nutrients[:fat]
    assert_equal 3.0, result.nutrients[:protein]
  end

  test 'ignores unknown lines gracefully' do
    text = <<~LABEL
      Serving size: 30g

      Calories          100
      Vitamin D         2mcg
      Total Fat         5g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 100.0, result.nutrients[:calories]
    assert_equal 5.0, result.nutrients[:fat]
  end

  test 'handles blank nutrient values as zero' do
    text = <<~LABEL
      Serving size: 30g

      Calories
      Total Fat
      Protein           3g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 0, result.nutrients[:calories]
    assert_equal 0, result.nutrients[:fat]
    assert_equal 3.0, result.nutrients[:protein]
  end

  test 'parses auto-portion from discrete serving size' do
    text = <<~LABEL
      Serving size: 1 slice (21g)

      Calories          60
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 21.0, result.nutrients[:basis_grams]
    assert_equal({ 'slice' => 21.0 }, result.portions)
    assert_nil result.density
  end

  test 'portions g suffix is optional' do
    text = <<~LABEL
      Serving size: 100g

      Calories          100

      Portions:
        stick: 113
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal 113.0, result.portions['stick']
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/services/nutrition_label_parser_test.rb`
Expected: Failures — `NutritionLabelParser` doesn't exist yet.

**Step 3: Implement NutritionLabelParser**

Create `app/services/nutrition_label_parser.rb`:

```ruby
# frozen_string_literal: true

class NutritionLabelParser
  Result = Data.define(:success?, :nutrients, :density, :portions, :errors) do
    def self.success(nutrients:, density:, portions:)
      new(success?: true, nutrients:, density:, portions:, errors: [])
    end

    def self.failure(errors)
      new(success?: false, nutrients: {}, density: nil, portions: {}, errors:)
    end
  end

  NUTRIENT_MAP = [
    [/\Acalories\z/i,                    :calories],
    [/\Atotal\s+fat\z/i,                 :fat],
    [/\Asaturated\s+fat\z/i,             :saturated_fat],
    [/\Atrans\s+fat\z/i,                 :trans_fat],
    [/\Acholesterol\z/i,                 :cholesterol],
    [/\Asodium\z/i,                      :sodium],
    [/\Atotal\s+carb(?:ohydrate)?s?\z/i, :carbs],
    [/\A(?:dietary\s+)?fiber\z/i,        :fiber],
    [/\Atotal\s+sugars?\z/i,             :total_sugars],
    [/\Aadded\s+sugars?\z/i,             :added_sugars],
    [/\Aprotein\z/i,                     :protein],
  ].freeze

  NUTRIENT_KEYS = NUTRIENT_MAP.map(&:last).freeze

  def self.parse(text)
    new(text).parse
  end

  def self.format(entry)
    new(nil).format_entry(entry)
  end

  def initialize(text)
    @text = text
  end

  def parse
    lines = @text.to_s.lines.map(&:rstrip)

    serving_line = extract_serving_line(lines)
    return Result.failure(['Serving size is required (e.g., "Serving size: 30g" or "Serving size: 1/4 cup (30g)")']) unless serving_line

    serving = NutritionEntryHelpers.parse_serving_size(serving_line)
    return Result.failure(['Could not parse gram weight from serving size. Include grams, e.g., "30g" or "1/4 cup (30g)".']) unless serving

    nutrients = parse_nutrients(lines)
    nutrients[:basis_grams] = serving[:grams]

    density = build_density(serving)
    portions = parse_portions(lines)
    portions = merge_auto_portion(portions, serving)

    Result.success(nutrients:, density:, portions:)
  end

  def format_entry(entry)
    lines = []
    lines << "Serving size: #{format_serving_size(entry)}"
    lines << ''

    NUTRIENT_MAP.each do |_pattern, key|
      value = entry.public_send(key)&.to_f || 0
      lines << format_nutrient_line(key, value)
    end

    portions = entry.portions || {}
    if portions.any?
      lines << ''
      lines << 'Portions:'
      portions.each { |name, grams| lines << "  #{name}: #{format_number(grams.to_f)}g" }
    end

    lines.join("\n")
  end

  private

  def extract_serving_line(lines)
    lines.each do |line|
      match = line.match(/\Aserving\s+size:\s*(.+)/i)
      return match[1].strip if match
    end
    nil
  end

  def parse_nutrients(lines)
    found = {}

    lines.each do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.match?(/\Aserving\s+size:/i) || stripped.match?(/\Aportions:/i)

      NUTRIENT_MAP.each do |pattern, key|
        next if found.key?(key)

        # Match "Nutrient Name    123g" or "Nutrient Name    123mg" or "Nutrient Name" (blank)
        name_part = stripped.gsub(/[\d.]+\s*(?:m?g)?\s*\z/i, '').strip
        next unless name_part.match?(pattern)

        value_match = stripped.match(/([\d.]+)\s*(?:m?g)?\s*\z/i)
        found[key] = value_match ? value_match[1].to_f : 0
        break
      end
    end

    NUTRIENT_KEYS.each_with_object({}) do |key, hash|
      hash[key] = found.fetch(key, 0)
    end
  end

  def parse_portions(lines)
    in_portions = false
    portions = {}

    lines.each do |line|
      if line.strip.match?(/\Aportions:\z/i)
        in_portions = true
        next
      end

      next unless in_portions

      break if line.strip.empty? && portions.any?
      next if line.strip.empty?

      match = line.match(/\A\s+([^:]+):\s*([\d.]+)\s*g?\s*\z/i)
      portions[match[1].strip] = match[2].to_f if match
    end

    portions
  end

  def build_density(serving)
    return unless serving[:volume_amount] && serving[:volume_unit]

    {
      grams: serving[:grams],
      volume: serving[:volume_amount],
      unit: serving[:volume_unit]
    }
  end

  def merge_auto_portion(portions, serving)
    return portions unless serving[:auto_portion]

    unit = serving[:auto_portion][:unit]
    grams = serving[:auto_portion][:grams]
    { unit => grams }.merge(portions)
  end

  def format_serving_size(entry)
    if entry.density_grams && entry.density_volume && entry.density_unit
      volume = format_number(entry.density_volume.to_f)
      "#{volume} #{entry.density_unit} (#{format_number(entry.density_grams.to_f)}g)"
    else
      "#{format_number(entry.basis_grams.to_f)}g"
    end
  end

  NUTRIENT_FORMAT = {
    calories:     ['Calories',       '',   0],
    fat:          ['Total Fat',      'g',  0],
    saturated_fat:['  Saturated Fat','g',  2],
    trans_fat:    ['  Trans Fat',    'g',  2],
    cholesterol:  ['Cholesterol',    'mg', 0],
    sodium:       ['Sodium',         'mg', 0],
    carbs:        ['Total Carbs',    'g',  0],
    fiber:        ['  Dietary Fiber','g',  2],
    total_sugars: ['  Total Sugars', 'g',  2],
    added_sugars: ['    Added Sugars','g', 4],
    protein:      ['Protein',        'g',  0],
  }.freeze

  def format_nutrient_line(key, value)
    label, unit, indent = NUTRIENT_FORMAT.fetch(key)
    value_str = value.zero? ? "0#{unit}" : "#{format_number(value)}#{unit}"
    padding = [20 - label.length, 1].max
    "#{label}#{' ' * padding}#{value_str}"
  end

  def format_number(value)
    value == value.to_i ? value.to_i.to_s : format('%.1f', value)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `rake test TEST=test/services/nutrition_label_parser_test.rb`
Expected: All pass.

**Step 5: Write formatter tests**

Add to `test/services/nutrition_label_parser_test.rb`:

```ruby
test 'formats entry with density as label text' do
  entry = NutritionEntry.new(
    basis_grams: 30, calories: 110, fat: 0.5, saturated_fat: 0, trans_fat: 0,
    cholesterol: 0, sodium: 0, carbs: 23, fiber: 1, total_sugars: 0, added_sugars: 0,
    protein: 3, density_grams: 30, density_volume: 0.25, density_unit: 'cup'
  )

  text = NutritionLabelParser.format(entry)

  assert_includes text, 'Serving size: 0.25 cup (30g)'
  assert_includes text, 'Calories'
  assert_includes text, '110'
  assert_includes text, 'Protein'
end

test 'formats entry without density' do
  entry = NutritionEntry.new(basis_grams: 100, calories: 717, fat: 81)

  text = NutritionLabelParser.format(entry)

  assert_includes text, 'Serving size: 100g'
end

test 'formats entry with portions' do
  entry = NutritionEntry.new(
    basis_grams: 100, calories: 717,
    portions: { 'stick' => 113.0, 'pat' => 5.0 }
  )

  text = NutritionLabelParser.format(entry)

  assert_includes text, 'Portions:'
  assert_includes text, 'stick: 113g'
  assert_includes text, 'pat: 5g'
end

test 'round-trips through parse and format' do
  entry = NutritionEntry.new(
    basis_grams: 30, calories: 110, fat: 0.5, saturated_fat: 0, trans_fat: 0,
    cholesterol: 0, sodium: 0, carbs: 23, fiber: 1, total_sugars: 0, added_sugars: 0,
    protein: 3, density_grams: 30, density_volume: 0.25, density_unit: 'cup',
    portions: { 'stick' => 113.0 }
  )

  text = NutritionLabelParser.format(entry)
  result = NutritionLabelParser.parse(text)

  assert_predicate result, :success?
  assert_equal 30.0, result.nutrients[:basis_grams]
  assert_equal 110.0, result.nutrients[:calories]
  assert_equal 'cup', result.density[:unit]
  assert_equal 113.0, result.portions['stick']
end
```

**Step 6: Run all parser tests**

Run: `rake test TEST=test/services/nutrition_label_parser_test.rb`
Expected: All pass.

**Step 7: Commit**

```bash
git add app/services/nutrition_label_parser.rb test/services/nutrition_label_parser_test.rb
git commit -m "feat: NutritionLabelParser for plaintext nutrition label parsing and formatting"
```

---

### Task 6: NutritionEntriesController — upsert and destroy

**Files:**
- Create: `app/controllers/nutrition_entries_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Add routes**

In `config/routes.rb`, inside the `scope 'kitchens/:kitchen_slug'` block, add:

```ruby
post 'nutrition/:ingredient_name', to: 'nutrition_entries#upsert', as: :nutrition_entry_upsert
delete 'nutrition/:ingredient_name', to: 'nutrition_entries#destroy', as: :nutrition_entry_destroy
```

Place these after the `groceries` routes but before the closing `end` of the scope block.

**Step 2: Write controller tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class NutritionEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    NutritionEntry.where(kitchen_id: [@kitchen.id, nil]).delete_all
  end

  test 'upsert creates kitchen-scoped entry from label text' do
    label = "Serving size: 30g\n\nCalories 100\nTotal Fat 5g\nProtein 3g"

    post nutrition_entry_upsert_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
         params: { label_text: label },
         as: :json

    assert_response :success

    entry = NutritionEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')
    assert entry
    assert_equal 30.0, entry.basis_grams.to_f
    assert_equal 100.0, entry.calories.to_f
    assert_equal 5.0, entry.fat.to_f
    assert_equal 3.0, entry.protein.to_f
    assert_predicate entry, :custom?
  end

  test 'upsert updates existing kitchen entry' do
    NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 100)

    label = "Serving size: 30g\n\nCalories 200\nProtein 5g"

    post nutrition_entry_upsert_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
         params: { label_text: label },
         as: :json

    assert_response :success

    entry = NutritionEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')
    assert_equal 200.0, entry.calories.to_f
    assert_equal 5.0, entry.protein.to_f
  end

  test 'upsert sets web source provenance' do
    label = "Serving size: 30g\n\nCalories 100"

    post nutrition_entry_upsert_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
         params: { label_text: label },
         as: :json

    entry = NutritionEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')
    assert_equal 'web', entry.sources.first['type']
  end

  test 'upsert returns errors for invalid label' do
    post nutrition_entry_upsert_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
         params: { label_text: 'no serving size here' },
         as: :json

    assert_response :unprocessable_entity
    errors = response.parsed_body['errors']
    assert errors.any? { |e| e.include?('Serving size') }
  end

  test 'upsert recalculates affected recipes' do
    NutritionEntry.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    recipe = MarkdownImporter.import(
      "# Bread\n\nCategory: Bread\nServes: 1\n\n## Mix\n\n- Flour, 30 g\n\nMix.",
      kitchen: @kitchen
    )

    label = "Serving size: 30g\n\nCalories 200"

    post nutrition_entry_upsert_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
         params: { label_text: label },
         as: :json

    recipe.reload
    assert_equal 200.0, recipe.nutrition_data['totals']['calories']
  end

  test 'upsert requires membership' do
    delete dev_logout_path
    label = "Serving size: 30g\n\nCalories 100"

    post nutrition_entry_upsert_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
         params: { label_text: label },
         as: :json

    assert_response :unauthorized
  end

  test 'destroy deletes kitchen override' do
    NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 100)

    delete nutrition_entry_destroy_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
           as: :json

    assert_response :success
    assert_nil NutritionEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')
  end

  test 'destroy does not delete global entries' do
    NutritionEntry.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)

    delete nutrition_entry_destroy_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
           as: :json

    assert_response :not_found
    assert NutritionEntry.find_by(kitchen_id: nil, ingredient_name: 'Flour')
  end

  test 'destroy requires membership' do
    delete dev_logout_path

    delete nutrition_entry_destroy_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
           as: :json

    assert_response :unauthorized
  end

  test 'destroy recalculates affected recipes' do
    NutritionEntry.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 200)

    recipe = MarkdownImporter.import(
      "# Bread\n\nCategory: Bread\nServes: 1\n\n## Mix\n\n- Flour, 30 g\n\nMix.",
      kitchen: @kitchen
    )

    delete nutrition_entry_destroy_path(kitchen_slug: kitchen_slug, ingredient_name: 'Flour'),
           as: :json

    recipe.reload
    # Falls back to global entry (110 cal)
    assert_equal 110.0, recipe.nutrition_data['totals']['calories']
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `rake test TEST=test/controllers/nutrition_entries_controller_test.rb`
Expected: Routing errors — controller doesn't exist.

**Step 4: Implement the controller**

Create `app/controllers/nutrition_entries_controller.rb`:

```ruby
# frozen_string_literal: true

class NutritionEntriesController < ApplicationController
  before_action :require_membership

  def upsert
    result = NutritionLabelParser.parse(params[:label_text])
    return render json: { errors: result.errors }, status: :unprocessable_entity unless result.success?

    entry = NutritionEntry.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    assign_parsed_attributes(entry, result)

    if entry.save
      recalculate_affected_recipes
      render json: { status: 'ok' }
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    entry = NutritionEntry.find_by!(kitchen: current_kitchen, ingredient_name:)
    entry.destroy!
    recalculate_affected_recipes
    render json: { status: 'ok' }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def ingredient_name
    params[:ingredient_name].tr('-', ' ')
  end

  def assign_parsed_attributes(entry, result)
    entry.assign_attributes(
      basis_grams: result.nutrients[:basis_grams],
      calories: result.nutrients[:calories],
      fat: result.nutrients[:fat],
      saturated_fat: result.nutrients[:saturated_fat],
      trans_fat: result.nutrients[:trans_fat],
      cholesterol: result.nutrients[:cholesterol],
      sodium: result.nutrients[:sodium],
      carbs: result.nutrients[:carbs],
      fiber: result.nutrients[:fiber],
      total_sugars: result.nutrients[:total_sugars],
      added_sugars: result.nutrients[:added_sugars],
      protein: result.nutrients[:protein],
      density_grams: result.density&.fetch(:grams, nil),
      density_volume: result.density&.fetch(:volume, nil),
      density_unit: result.density&.fetch(:unit, nil),
      portions: result.portions,
      sources: [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }]
    )
  end

  def recalculate_affected_recipes
    recipes = find_affected_recipes
    recipes.each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end

  def find_affected_recipes
    canonical = ingredient_name.downcase
    current_kitchen.recipes.includes(steps: :ingredients).select do |recipe|
      recipe.ingredients.any? { |i| i.name.downcase == canonical }
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `rake test TEST=test/controllers/nutrition_entries_controller_test.rb`
Expected: All pass.

**Step 6: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb config/routes.rb test/controllers/nutrition_entries_controller_test.rb
git commit -m "feat: NutritionEntriesController with upsert and destroy actions"
```

---

### Task 7: Redesign ingredients page — controller, view, and nav

**Files:**
- Modify: `app/controllers/ingredients_controller.rb`
- Modify: `app/views/ingredients/index.html.erb`
- Modify: `app/views/shared/_nav.html.erb`
- Modify: `test/controllers/ingredients_controller_test.rb`

**Step 1: Update existing tests and add new ones**

In `test/controllers/ingredients_controller_test.rb`, update the page title assertion and add nutrition status tests:

Update the first test's assertion from `assert_select 'h1', 'Ingredient Index'` to `assert_select 'h1', 'Ingredients'`.

Add these tests:

```ruby
test 'shows missing nutrition badge for ingredients without data' do
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.nutrition-missing'
end

test 'shows global badge for ingredients with global nutrition data' do
  NutritionEntry.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.nutrition-global'
end

test 'shows custom badge for ingredients with kitchen override' do
  NutritionEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110)
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.nutrition-custom'
end

test 'shows missing ingredients banner when nutrition data is absent' do
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'details.nutrition-banner'
end

test 'hides edit controls from non-members' do
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.nutrition-edit-btn', count: 0
  assert_select '.editor-dialog', count: 0
end
```

**Step 2: Run new tests to verify they fail**

Run: `rake test TEST=test/controllers/ingredients_controller_test.rb`
Expected: Failures on new tests (badges, banner not rendered yet). Existing title test fails too.

**Step 3: Update IngredientsController**

Replace `app/controllers/ingredients_controller.rb`:

```ruby
# frozen_string_literal: true

class IngredientsController < ApplicationController
  def index
    @alias_map = load_alias_map
    @ingredients_with_recipes = build_ingredient_index
    @nutrition_lookup = NutritionEntry.lookup_for(current_kitchen)
    @missing_ingredients = find_missing_ingredients
  end

  private

  def build_ingredient_index
    index = recipes_by_ingredient
    index.sort_by { |name, _| name.downcase }
  end

  def recipes_by_ingredient
    recipes = current_kitchen.recipes.includes(steps: :ingredients)
    recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        canonical = @alias_map[ingredient.name.downcase] || ingredient.name
        index[canonical] << recipe unless index[canonical].include?(recipe)
      end
    end
  end

  def find_missing_ingredients
    @ingredients_with_recipes.filter_map do |name, _recipes|
      name unless @nutrition_lookup.key?(name)
    end
  end

  def load_alias_map
    FamilyRecipes.build_alias_map(load_grocery_aisles)
  end

  def load_grocery_aisles
    content = SiteDocument.content_for('grocery_aisles')
    return FamilyRecipes.parse_grocery_aisles_markdown(content) if content

    FamilyRecipes.parse_grocery_info(Rails.root.join('db/seeds/resources/grocery-info.yaml'))
  end
end
```

**Step 4: Update the view**

Replace `app/views/ingredients/index.html.erb`:

```erb
<% content_for(:title) { "#{current_kitchen.name}: Ingredients" } %>

<article class="index ingredients">
  <header>
    <h1>Ingredients</h1>
  </header>

  <%- if current_kitchen.member?(current_user) && @missing_ingredients.any? -%>
  <details class="nutrition-banner">
    <summary><%= @missing_ingredients.size %> ingredient<%= 's' unless @missing_ingredients.size == 1 %> need<%= 's' if @missing_ingredients.size == 1 %> nutrition data</summary>
    <p class="nutrition-banner-list">
      <%- @missing_ingredients.each_with_index do |name, i| -%>
        <% unless i.zero? %> · <% end -%>
        <a href="#ingredient-<%= name.parameterize %>" class="nutrition-banner-link"><%= name %></a>
      <%- end -%>
    </p>
  </details>
  <%- end -%>

  <%- @ingredients_with_recipes.each do |ingredient, recipes| -%>
  <section id="ingredient-<%= ingredient.parameterize %>">
    <h2>
      <%= ingredient %>
      <%- if current_kitchen.member?(current_user) -%>
        <%- entry = @nutrition_lookup[ingredient] -%>
        <%- if entry.nil? -%>
          <span class="nutrition-badge nutrition-missing" title="No nutrition data">!</span>
          <button type="button" class="btn-link nutrition-edit-btn"
                  data-ingredient="<%= ingredient %>"
                  data-nutrition-text="<%= NutritionLabelParser.blank_skeleton %>">+ Add nutrition</button>
        <%- elsif entry.global? -%>
          <span class="nutrition-badge nutrition-global" title="Built-in nutrition data">built-in</span>
          <button type="button" class="btn-link nutrition-edit-btn"
                  data-ingredient="<%= ingredient %>"
                  data-nutrition-text="<%= NutritionLabelParser.format(entry) %>">Edit</button>
        <%- else -%>
          <span class="nutrition-badge nutrition-custom" title="Custom nutrition data">custom</span>
          <button type="button" class="btn-link nutrition-edit-btn"
                  data-ingredient="<%= ingredient %>"
                  data-nutrition-text="<%= NutritionLabelParser.format(entry) %>">Edit</button>
          <button type="button" class="btn-link nutrition-reset-btn"
                  data-ingredient="<%= ingredient %>">Reset</button>
        <%- end -%>
      <%- end -%>
    </h2>
    <ul>
      <%- recipes.each do |recipe| -%>
      <li><%= link_to recipe.title, recipe_path(recipe.slug), title: recipe.description %></li>
      <%- end -%>
    </ul>
  </section>
  <%- end -%>
</article>

<% if current_kitchen.member?(current_user) %>
<dialog id="nutrition-editor" class="editor-dialog">
  <div class="editor-header">
    <h2 id="nutrition-editor-title">Edit Nutrition</h2>
    <button type="button" class="btn editor-close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" hidden></div>
  <textarea id="nutrition-editor-textarea" class="editor-textarea" spellcheck="false"></textarea>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary editor-save">Save</button>
  </div>
</dialog>

<%= javascript_include_tag 'nutrition-editor' %>
<% end %>
```

**Step 5: Add `blank_skeleton` class method to NutritionLabelParser**

In `app/services/nutrition_label_parser.rb`, add:

```ruby
def self.blank_skeleton
  lines = ['Serving size:', '']
  NUTRIENT_MAP.each do |_pattern, key|
    label, _unit, _indent = NUTRIENT_FORMAT.fetch(key)
    lines << label
  end
  lines.join("\n")
end
```

**Step 6: Update nav link**

In `app/views/shared/_nav.html.erb`, change:
```erb
<%= link_to 'Index', ingredients_path, class: 'index', title: 'Index of ingredients' %>
```
to:
```erb
<%= link_to 'Ingredients', ingredients_path, class: 'ingredients', title: 'Ingredients' %>
```

**Step 7: Run tests**

Run: `rake test TEST=test/controllers/ingredients_controller_test.rb`
Expected: All pass (update first test's h1 assertion from 'Ingredient Index' to 'Ingredients').

**Step 8: Commit**

```bash
git add app/controllers/ingredients_controller.rb app/views/ingredients/index.html.erb app/views/shared/_nav.html.erb app/services/nutrition_label_parser.rb test/controllers/ingredients_controller_test.rb
git commit -m "feat: redesign ingredients page with nutrition status badges and editor dialog"
```

---

### Task 8: Nutrition editor JavaScript — dialog handler

**Files:**
- Create: `app/assets/javascripts/nutrition-editor.js`

The nutrition editor dialog doesn't use the standard `editor-dialog` data-attribute pattern because it's a single shared dialog populated dynamically by multiple buttons. It needs a small custom handler.

**Step 1: Implement the nutrition editor JS**

Create `app/assets/javascripts/nutrition-editor.js`:

```javascript
document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('nutrition-editor');
  if (!dialog) return;

  const textarea = document.getElementById('nutrition-editor-textarea');
  const titleEl = document.getElementById('nutrition-editor-title');
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const errorsDiv = dialog.querySelector('.editor-errors');
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

  let currentIngredient = null;
  let originalContent = '';
  let saving = false;

  function isModified() {
    return textarea.value !== originalContent;
  }

  function showErrors(errors) {
    const list = document.createElement('ul');
    errors.forEach(msg => {
      const li = document.createElement('li');
      li.textContent = msg;
      list.appendChild(li);
    });
    errorsDiv.replaceChildren(list);
    errorsDiv.hidden = false;
  }

  function clearErrors() {
    errorsDiv.replaceChildren();
    errorsDiv.hidden = true;
  }

  function closeDialog() {
    if (isModified() && !confirm('You have unsaved changes. Discard them?')) return;
    textarea.value = originalContent;
    clearErrors();
    dialog.close();
  }

  function nutritionUrl(name) {
    const slug = name.replace(/ /g, '-');
    const base = window.location.pathname.replace(/\/index\/?$/, '').replace(/\/$/, '');
    return base.replace(/\/[^/]*$/, '') + '/nutrition/' + encodeURIComponent(slug);
  }

  // Open from edit/add buttons
  document.querySelectorAll('.nutrition-edit-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      currentIngredient = btn.dataset.ingredient;
      textarea.value = btn.dataset.nutritionText;
      originalContent = textarea.value;
      titleEl.textContent = currentIngredient;
      clearErrors();
      dialog.showModal();
    });
  });

  // Reset buttons (delete kitchen override)
  document.querySelectorAll('.nutrition-reset-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const name = btn.dataset.ingredient;
      if (!confirm(`Reset "${name}" to built-in nutrition data?`)) return;

      btn.disabled = true;
      try {
        const response = await fetch(nutritionUrl(name), {
          method: 'DELETE',
          headers: { 'X-CSRF-Token': csrfToken }
        });

        if (response.ok) {
          window.location.reload();
        } else {
          btn.disabled = false;
          alert('Failed to reset. Please try again.');
        }
      } catch {
        btn.disabled = false;
        alert('Network error. Please try again.');
      }
    });
  });

  closeBtn.addEventListener('click', closeDialog);
  cancelBtn.addEventListener('click', closeDialog);

  dialog.addEventListener('cancel', (event) => {
    if (isModified()) {
      event.preventDefault();
      closeDialog();
    }
  });

  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving\u2026';
    clearErrors();

    try {
      const response = await fetch(nutritionUrl(currentIngredient), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ label_text: textarea.value })
      });

      if (response.ok) {
        saving = true;
        window.location.reload();
      } else if (response.status === 422) {
        const data = await response.json();
        showErrors(data.errors);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      } else {
        showErrors([`Server error (${response.status}). Please try again.`]);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      }
    } catch {
      showErrors(['Network error. Please check your connection and try again.']);
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save';
    }
  });

  window.addEventListener('beforeunload', (event) => {
    if (!saving && dialog.open && isModified()) {
      event.preventDefault();
    }
  });
});
```

**Step 2: Verify manually**

Run: `bin/dev`
Navigate to the ingredients page. Click an edit/add button. The dialog should open with pre-filled or blank content. Submit should save and reload.

**Step 3: Commit**

```bash
git add app/assets/javascripts/nutrition-editor.js
git commit -m "feat: nutrition editor dialog JS for ingredients page"
```

---

### Task 9: CSS styles for nutrition badges and banner

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add nutrition-specific styles**

Add to `style.css` after the existing `.index section h2` styles (around line 422):

```css
/* Nutrition status badges and banner */
.nutrition-banner {
  margin: 0 0 1.5rem;
  padding: 0.75rem 1rem;
  background: #fef3cd;
  border: 1px solid #e6d17a;
  border-radius: 0.25rem;
  font-size: 0.9rem;
}

.nutrition-banner summary {
  cursor: pointer;
  font-weight: 600;
}

.nutrition-banner-list {
  margin: 0.5rem 0 0;
  line-height: 1.8;
}

.nutrition-banner-link {
  white-space: nowrap;
}

.nutrition-badge {
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.1em 0.4em;
  border-radius: 0.2em;
  vertical-align: middle;
  margin-left: 0.3em;
}

.nutrition-missing {
  background: #f8d7da;
  color: #721c24;
}

.nutrition-global {
  background: #d4edda;
  color: #155724;
}

.nutrition-custom {
  background: #cce5ff;
  color: #004085;
}

.btn-link {
  background: none;
  border: none;
  color: var(--muted-text);
  font-size: 0.75rem;
  cursor: pointer;
  padding: 0;
  text-decoration: underline;
  vertical-align: middle;
}

.btn-link:hover {
  color: var(--text-color);
}
```

**Step 2: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: CSS styles for nutrition badges, banner, and edit links"
```

---

### Task 10: Update existing tests — fix broken assertions

**Files:**
- Modify: various test files that reference acts_as_tenant for NutritionEntry

**Step 1: Run full test suite**

Run: `rake test`

Identify any failures caused by:
- NutritionEntry no longer using `acts_as_tenant` (tests that relied on implicit kitchen scoping)
- Page title change from "Ingredient Index" to "Ingredients"
- Nav link text change from "Index" to "Ingredients"

**Step 2: Fix each failure**

Common fixes:
- Tests creating `NutritionEntry` without explicit `kitchen:` now create global entries (this may be desired or need `kitchen: @kitchen` added)
- `assert_select 'h1', 'Ingredient Index'` → `assert_select 'h1', 'Ingredients'`
- Nav assertions checking for "Index" link text → "Ingredients"

**Step 3: Run full test suite again**

Run: `rake test`
Expected: All pass.

**Step 4: Run lint**

Run: `rake lint`
Expected: No offenses. Fix any RuboCop issues.

**Step 5: Commit**

```bash
git add -A
git commit -m "fix: update tests for nutrition overlay model and ingredients page rename"
```

---

### Task 11: Manual verification and polish

**Step 1: Start dev server**

Run: `bin/dev`

**Step 2: Verify ingredients page**

- Navigate to `/kitchens/biagini-family/index`
- Confirm page title says "Ingredients"
- Confirm nav link says "Ingredients"
- Confirm missing ingredients banner appears (if any ingredients lack nutrition data)
- Confirm badges show correct status (global/custom/missing)
- Log out and confirm edit controls are hidden

**Step 3: Test the editor dialog**

- Click "Add nutrition" on a missing ingredient → blank skeleton appears
- Enter label data and save → entry created, page reloads with badge change
- Click "Edit" on a global ingredient → pre-filled data appears
- Save → creates kitchen override (badge changes from "built-in" to "custom")
- Click "Reset" on a custom ingredient → override deleted, falls back to global
- Submit invalid data (no serving size) → error message displayed in dialog

**Step 4: Verify nutrition recalculation**

- Edit nutrition for an ingredient used in recipes
- Check that recipe nutrition tables update after save

**Step 5: Fix any issues found**

Address visual polish, error handling edge cases, or accessibility issues.

**Step 6: Final commit if any fixes**

```bash
git add -A
git commit -m "fix: polish nutrition editor from manual testing"
```

---

### Task 12: Final test suite and lint

**Step 1: Run full test suite**

Run: `rake`
Expected: All tests pass, lint clean.

**Step 2: Commit any remaining fixes**

---

### Task Summary

| Task | Description | Depends on |
|------|-------------|------------|
| 0 | Create worktree | — |
| 1 | Migration: nullable kitchen_id | 0 |
| 2 | NutritionEntry overlay model | 1 |
| 3 | Update seeds for global entries | 2 |
| 4 | RecipeNutritionJob overlay lookup | 2 |
| 5 | NutritionLabelParser service | 0 |
| 6 | NutritionEntriesController | 2, 5 |
| 7 | Ingredients page redesign | 2, 5 |
| 8 | Nutrition editor JS | 7 |
| 9 | CSS for badges and banner | 7 |
| 10 | Fix broken tests | all above |
| 11 | Manual verification | all above |
| 12 | Final test suite and lint | 11 |
