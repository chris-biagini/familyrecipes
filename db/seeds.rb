# frozen_string_literal: true

# Create kitchen and user
kitchen = Kitchen.find_or_create_by!(slug: 'biagini-family') do |k|
  k.name = 'Biagini Family'
end

user = User.find_or_create_by!(email: 'chris@example.com') do |u|
  u.name = 'Chris'
end

ActsAsTenant.current_tenant = kitchen
Membership.find_or_create_by!(kitchen: kitchen, user: user)

puts "Kitchen: #{kitchen.name} (#{kitchen.slug})"
puts "User: #{user.name} (#{user.email})"

# Import recipes
seeds_dir = Rails.root.join('db/seeds')
recipes_dir = seeds_dir.join('recipes')
resources_dir = seeds_dir.join('resources')
quick_bites_filename = 'Quick Bites.md'

recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
  File.basename(path) == quick_bites_filename
end

puts "Importing #{recipe_files.size} recipes..."

recipe_files.each do |path|
  markdown = File.read(path)
  tokens = LineClassifier.classify(markdown)
  parsed = RecipeBuilder.new(tokens).build
  slug = FamilyRecipes.slugify(parsed[:title])

  existing = kitchen.recipes.find_by(slug: slug)
  if existing&.edited_at?
    puts "  [skipped] #{existing.title} (web-edited)"
    next
  end

  recipe = MarkdownImporter.import(markdown, kitchen: kitchen)
  puts "  #{recipe.title} (#{recipe.category.name})"
end

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."

# Seed Quick Bites content on kitchen
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  kitchen.update!(quick_bites_content: File.read(quick_bites_path)) unless kitchen.quick_bites_content
  puts 'Quick Bites content loaded.'
end

# Seed IngredientCatalog rows from nutrition data
nutrition_path = resources_dir.join('nutrition-data.yaml')
if File.exist?(nutrition_path)
  raw_content = File.read(nutrition_path)
  nutrition_data = YAML.safe_load(raw_content, permitted_classes: [], permitted_symbols: [], aliases: false)
  nutrition_data.each do |name, entry|
    nutrients = entry['nutrients']
    next unless nutrients.is_a?(Hash) && nutrients['basis_grams'].is_a?(Numeric)

    density = entry['density'] || {}
    IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name).tap do |ne|
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
  puts "Seeded #{IngredientCatalog.global.count} nutrition entries."
end

# Populate aisle data on IngredientCatalog rows from grocery-info.yaml
grocery_yaml_path = resources_dir.join('grocery-info.yaml')
if File.exist?(grocery_yaml_path)
  raw = YAML.safe_load_file(grocery_yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)
  aisle_count = 0

  raw.each do |aisle, items|
    # Normalize "Omit_From_List" to "omit"
    aisle_value = aisle.downcase.tr('_', ' ') == 'omit from list' ? 'omit' : aisle

    items.each do |item|
      name = item.is_a?(Hash) ? item['name'] : item
      profile = IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name)
      profile.aisle = aisle_value
      profile.save!
      aisle_count += 1
    end
  end

  puts "Populated aisle data on #{aisle_count} ingredient profiles."
end
