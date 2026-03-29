# frozen_string_literal: true

# Populates a fresh database with a default kitchen, user, sample recipes,
# Quick Bites, and aisle ordering. Only installs sample content on first boot
# (when no recipes exist). Kitchen, user, and aisle order are always idempotent.
#
# Collaborators:
# - MarkdownImporter — parses and persists each recipe Markdown file
# - CrossReference.resolve_pending — links deferred @[Title] references
# - catalog:sync rake task — reused here so catalog exists before recipe import
# - db/seeds/recipes/ — sample Markdown files including Quick Bites.md
# - db/seeds/resources/ — aisle-order.txt and ingredient-catalog.yaml
def sync_front_matter_tags(kitchen, result)
  return unless result.front_matter_tags

  tags = result.front_matter_tags.map { |n| kitchen.tags.find_or_create_by!(name: n.downcase) }
  result.recipe.tags = tags
end

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

# Sync ingredient catalog (idempotent — always update to latest).
# Must run before recipe import so RecipeNutritionJob can compute nutrition.
# db:prepare calls db:seed internally, before the entrypoint's catalog:sync.
Rake::Task['catalog:sync'].invoke

# Seed aisle order (idempotent — always update to latest)
seeds_dir = Rails.root.join('db/seeds')
aisle_order_path = seeds_dir.join('resources/aisle-order.txt')
if aisle_order_path.exist?
  kitchen.update!(aisle_order: File.read(aisle_order_path, encoding: 'utf-8').strip)
  puts 'Aisle order loaded.'
end

# Sample content — first boot only (skip in test env)
if Recipe.none? && !Rails.env.test?
  recipes_dir = seeds_dir.join('recipes')
  quick_bites_filename = 'Quick Bites.md'

  recipe_files = Dir.glob(recipes_dir.join('*.md')).reject do |path|
    File.basename(path) == quick_bites_filename
  end

  puts "Importing #{recipe_files.size} sample recipes..."

  recipe_files.each do |path|
    result = MarkdownImporter.import(File.read(path, encoding: 'utf-8'), kitchen: kitchen, category: nil)
    sync_front_matter_tags(kitchen, result)
    puts "  #{result.recipe.title} (#{result.recipe.category.name})"
  end

  CrossReference.resolve_pending(kitchen: kitchen)
  pending_count = CrossReference.pending.count
  puts "  WARNING: #{pending_count} unresolved cross-references remain" if pending_count.positive?

  quick_bites_path = recipes_dir.join(quick_bites_filename)
  if quick_bites_path.exist?
    QuickBitesWriteService.update(kitchen: kitchen, content: File.read(quick_bites_path, encoding: 'utf-8'))
    puts 'Quick Bites content loaded.'
  end

  puts "Done! #{Recipe.count} recipes in #{Category.count} categories."
else
  puts "Recipes already exist (#{Recipe.count}) — skipping sample content."
end
