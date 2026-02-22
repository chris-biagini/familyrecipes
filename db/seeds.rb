# frozen_string_literal: true

recipes_dir = Rails.root.join('recipes')
quick_bites_filename = 'Quick Bites.md'

recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
  File.basename(path) == quick_bites_filename
end

puts "Importing #{recipe_files.size} recipes..."

recipe_files.each do |path|
  markdown = File.read(path)
  recipe = MarkdownImporter.import(markdown)
  puts "  #{recipe.title} (#{recipe.category.name})"
end

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."
