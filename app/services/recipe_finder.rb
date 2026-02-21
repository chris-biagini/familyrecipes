# frozen_string_literal: true

class RecipeFinder
  RECIPES_DIR = Rails.root.join('recipes')
  QUICK_BITES_FILENAME = 'Quick Bites.md'

  def self.find_by_slug(slug)
    path = slug_to_path[slug]
    return unless path

    source = File.read(path)
    category = extract_category(source)
    FamilyRecipes::Recipe.new(markdown_source: source, id: slug, category: category)
  end

  def self.slug_to_path
    @slug_to_path ||= Dir.glob(RECIPES_DIR.join('**', '*.md'))
                         .reject { |p| File.basename(p) == QUICK_BITES_FILENAME }
                         .to_h { |p| [FamilyRecipes.slugify(File.basename(p, '.*')), p] }
  end
  private_class_method :slug_to_path

  def self.reset_cache!
    @slug_to_path = nil
  end

  def self.extract_category(source)
    source[/^Category:\s*(.+)/, 1]&.strip
  end
  private_class_method :extract_category
end
