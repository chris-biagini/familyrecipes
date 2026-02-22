# frozen_string_literal: true

# Create kitchen and user
kitchen = Kitchen.find_or_create_by!(slug: 'biagini-family') do |k|
  k.name = 'Biagini Family'
end

user = User.find_or_create_by!(email: 'chris@example.com') do |u|
  u.name = 'Chris'
end

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

# Seed Quick Bites document
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'quick_bites') do |doc|
    doc.content = File.read(quick_bites_path)
  end
  puts 'Quick Bites document loaded.'
end

# Seed Grocery Aisles document (convert YAML to markdown)
grocery_yaml_path = resources_dir.join('grocery-info.yaml')
if File.exist?(grocery_yaml_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'grocery_aisles') do |doc|
    raw = YAML.safe_load_file(grocery_yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    doc.content = raw.map do |aisle, items|
      heading = "## #{aisle.tr('_', ' ')}"
      item_lines = items.map do |item|
        name = item.respond_to?(:fetch) ? item.fetch('name') : item
        "- #{name}"
      end
      [heading, *item_lines, ''].join("\n")
    end.join("\n")
  end
  puts 'Grocery Aisles document loaded.'
end

# Seed Site Config document
site_config_path = resources_dir.join('site-config.yaml')
if File.exist?(site_config_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'site_config') do |doc|
    doc.content = File.read(site_config_path)
  end
  puts 'Site Config document loaded.'
end

# Seed Nutrition Data document
nutrition_path = resources_dir.join('nutrition-data.yaml')
if File.exist?(nutrition_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'nutrition_data') do |doc|
    doc.content = File.read(nutrition_path)
  end
  puts 'Nutrition Data document loaded.'
end
