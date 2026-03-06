# frozen_string_literal: true

# Populates a fresh database with a default kitchen, user, recipes, Quick Bites,
# and aisle ordering from seed files under db/seeds/. Skips web-edited recipes
# so re-running seeds won't clobber user changes. Also resolves any deferred
# cross-references after all recipes are imported.
#
# Collaborators:
# - MarkdownImporter — parses and persists each recipe Markdown file
# - CrossReference.resolve_pending — links deferred @[Title] references
# - db/seeds/recipes/ — source Markdown files including Quick Bites.md
# - db/seeds/resources/ — aisle-order.txt for grocery aisle display order
kitchen = Kitchen.find_or_create_by!(slug: 'our-kitchen') do |k|
  k.name = 'Our Kitchen'
end

user = User.find_or_create_by!(email: 'user@example.com') do |u|
  u.name = 'Home Cook'
end

ActsAsTenant.current_tenant = kitchen
Membership.find_or_create_by!(kitchen: kitchen, user: user)

puts "Kitchen: #{kitchen.name} (#{kitchen.slug})"
puts "User: #{user.name} (#{user.email})"

# Import recipes
seeds_dir = Rails.root.join('db/seeds')
recipes_dir = seeds_dir.join('recipes')
quick_bites_filename = 'Quick Bites.md'

recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
  File.basename(path) == quick_bites_filename
end

puts "Importing #{recipe_files.size} recipes..."

recipe_files.each do |path|
  markdown = File.read(path)
  category_name = File.basename(File.dirname(path))

  tokens = LineClassifier.classify(markdown)
  parsed = RecipeBuilder.new(tokens).build
  slug = FamilyRecipes.slugify(parsed[:title])

  existing = kitchen.recipes.find_by(slug: slug)
  if existing&.edited_at?
    puts "  [skipped] #{existing.title} (web-edited)"
    next
  end

  category_slug = FamilyRecipes.slugify(category_name)
  category = kitchen.categories.find_or_create_by!(slug: category_slug) do |cat|
    cat.name = category_name
    cat.position = kitchen.categories.maximum(:position).to_i + 1
  end

  recipe = MarkdownImporter.import(markdown, kitchen: kitchen, category: category)
  puts "  #{recipe.title} (#{recipe.category.name})"
end

# Resolve any cross-references that were deferred during import
CrossReference.resolve_pending(kitchen: kitchen)
pending_count = CrossReference.pending.count
puts "  WARNING: #{pending_count} unresolved cross-references remain" if pending_count.positive?

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."

# Seed aisle order
aisle_order_path = seeds_dir.join('resources/aisle-order.txt')
if File.exist?(aisle_order_path)
  kitchen.update!(aisle_order: File.read(aisle_order_path).strip)
  puts 'Aisle order loaded.'
end

# Seed Quick Bites content onto kitchen
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  kitchen.update!(quick_bites_content: File.read(quick_bites_path))
  puts 'Quick Bites content loaded.'
end
