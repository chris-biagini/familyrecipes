# frozen_string_literal: true

# Create kitchen and user
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

# Resolve any cross-references that were deferred during import
CrossReference.resolve_pending(kitchen: kitchen)
pending_count = CrossReference.pending.count
puts "  WARNING: #{pending_count} unresolved cross-references remain" if pending_count.positive?

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."

# Seed Quick Bites content onto kitchen
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  kitchen.update!(quick_bites_content: File.read(quick_bites_path))
  puts 'Quick Bites content loaded.'
end
