# frozen_string_literal: true

# Seeds the database from Markdown recipe files and nutrition YAML.
# Idempotent: running twice produces no duplicates.

require_relative '../lib/familyrecipes'

RECIPES_DIR = Rails.root.join('recipes').to_s
NUTRITION_PATH = Rails.root.join('resources', 'nutrition-data.yaml').to_s

# ---------------------------------------------------------------------------
# 1. Full recipes (two-pass)
# ---------------------------------------------------------------------------

def seed_recipes
  puts 'Seeding recipes...'
  recipes = FamilyRecipes.parse_recipes(RECIPES_DIR)

  # First pass: create/update all RecipeRecord shells so cross-reference targets exist
  recipe_records = recipes.each_with_object({}) do |recipe, map|
    record = RecipeRecord.find_or_initialize_by(slug: recipe.id)
    record.assign_attributes(
      title: recipe.title,
      description: recipe.description,
      category: recipe.category,
      makes: recipe.makes,
      serves: recipe.serves,
      footer: recipe.footer,
      source_markdown: recipe.source,
      version_hash: recipe.version_hash,
      quick_bite: false
    )
    record.save!
    map[recipe.id] = { record:, domain: recipe }
  end

  # Second pass: populate steps, ingredients, and cross-references
  recipe_records.each_value do |entry|
    record = entry[:record]
    recipe = entry[:domain]

    # Destroy existing children for idempotent re-seeding (cascades via dependent: :destroy)
    record.step_records.destroy_all

    recipe.steps.each_with_index do |step, step_index|
      step_record = record.step_records.create!(
        position: step_index,
        tldr: step.tldr,
        instructions: step.instructions
      )

      seed_step_items(step, step_record, record)
    end
  end

  puts "#{recipes.size} recipes seeded."
  recipes.size
end

def seed_step_items(step, step_record, recipe_record)
  step.ingredient_list_items.each_with_index do |item, position|
    case item
    when Ingredient
      IngredientRecord.create!(
        recipe_record:,
        step_record:,
        position:,
        name: item.name,
        quantity: item.quantity,
        prep_note: item.prep_note
      )
    when CrossReference
      target = RecipeRecord.find_by!(slug: item.target_slug)
      CrossReferenceRecord.create!(
        recipe_record:,
        step_record:,
        target_recipe: target,
        position:,
        multiplier: item.multiplier,
        prep_note: item.prep_note
      )
    end
  end
end

# ---------------------------------------------------------------------------
# 2. Quick Bites
# ---------------------------------------------------------------------------

def seed_quick_bites
  puts 'Seeding Quick Bites...'
  quick_bites = FamilyRecipes.parse_quick_bites(RECIPES_DIR)

  quick_bites.each do |qb|
    record = RecipeRecord.find_or_initialize_by(slug: qb.id)
    record.assign_attributes(
      title: qb.title,
      category: qb.category,
      source_markdown: qb.text_source,
      version_hash: Digest::SHA256.hexdigest(qb.text_source),
      quick_bite: true,
      description: nil,
      makes: nil,
      serves: nil,
      footer: nil
    )
    record.save!

    # Clear existing step-less ingredients, then recreate
    record.ingredient_records.where(step_id: nil).destroy_all

    qb.ingredients.each_with_index do |name, position|
      IngredientRecord.create!(
        recipe_record: record,
        step_record: nil,
        position:,
        name:
      )
    end
  end

  puts "#{quick_bites.size} quick bites seeded."
  quick_bites.size
end

# ---------------------------------------------------------------------------
# 3. Nutrition data
# ---------------------------------------------------------------------------

def seed_nutrition
  puts 'Seeding nutrition data...'
  data = YAML.safe_load_file(NUTRITION_PATH, permitted_classes: [], permitted_symbols: [], aliases: false)

  data.each do |ingredient_name, entry|
    nutrients = entry['nutrients']
    density = entry['density']

    record = NutritionEntryRecord.find_or_initialize_by(ingredient_name:)
    record.assign_attributes(
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
      density_grams: density&.fetch('grams', nil),
      density_volume: density&.fetch('volume', nil),
      density_unit: density&.fetch('unit', nil),
      portions: entry['portions'],
      sources: entry['sources']
    )
    record.save!
  end

  puts "#{data.size} nutrition entries seeded."
  data.size
end

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

ActiveRecord::Base.transaction do
  seed_recipes
  seed_quick_bites
  seed_nutrition
end

puts 'Done!'
