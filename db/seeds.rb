# frozen_string_literal: true

# Populates a fresh database with a default kitchen, user, sample recipes,
# Quick Bites, and aisle ordering. Only installs sample content on first boot
# (when no recipes exist). Kitchen, user, and aisle order are always idempotent.
#
# Collaborators:
# - MarkdownImporter — parses and persists each recipe Markdown file
# - CrossReference.resolve_pending — links deferred @[Title] references
# - db/seeds/recipes/ — sample Markdown files including Quick Bites.md
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

# Seed aisle order (idempotent — always update to latest)
seeds_dir = Rails.root.join('db/seeds')
aisle_order_path = seeds_dir.join('resources/aisle-order.txt')
if aisle_order_path.exist?
  kitchen.update!(aisle_order: File.read(aisle_order_path).strip)
  puts 'Aisle order loaded.'
end

# Sample content — first boot only
if Recipe.count.zero?
  recipes_dir = seeds_dir.join('recipes')
  quick_bites_filename = 'Quick Bites.md'

  recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
    File.basename(path) == quick_bites_filename
  end

  puts "Importing #{recipe_files.size} sample recipes..."

  recipe_files.each do |path|
    category_name = File.basename(File.dirname(path))
    category_slug = FamilyRecipes.slugify(category_name)
    category = kitchen.categories.find_or_create_by!(slug: category_slug) do |cat|
      cat.name = category_name
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end

    recipe = MarkdownImporter.import(File.read(path), kitchen: kitchen, category: category)
    puts "  #{recipe.title} (#{recipe.category.name})"
  end

  CrossReference.resolve_pending(kitchen: kitchen)
  pending_count = CrossReference.pending.count
  puts "  WARNING: #{pending_count} unresolved cross-references remain" if pending_count.positive?

  quick_bites_path = recipes_dir.join(quick_bites_filename)
  if quick_bites_path.exist?
    kitchen.update!(quick_bites_content: File.read(quick_bites_path))
    puts 'Quick Bites content loaded.'
  end

  puts "Done! #{Recipe.count} recipes in #{Category.count} categories."
else
  puts "Recipes already exist (#{Recipe.count}) — skipping sample content."
end
