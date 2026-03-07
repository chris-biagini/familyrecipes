# frozen_string_literal: true

# Processes uploaded files for import into a kitchen. Accepts ZIP archives
# (matching export format) or individual recipe files (.md, .txt, .text).
# Routes each file to the appropriate handler: RecipeWriteService for recipes,
# CatalogWriteService for ingredient catalog entries, direct assignment for
# Quick Bites.
#
# - RecipeWriteService: recipe upsert (create or overwrite by slug)
# - CatalogWriteService: ingredient catalog upsert by name
# - Kitchen: tenant container receiving imported data
# - ExportService: produces the ZIP format this service consumes
class ImportService
  Result = Data.define(:recipes, :ingredients, :quick_bites, :errors) do
    def self.empty
      new(recipes: 0, ingredients: 0, quick_bites: false, errors: [])
    end
  end

  RECIPE_EXTENSIONS = %w[.md .txt .text].freeze
  QUICK_BITES_PATTERN = /\Aquick[- ]?bites\z/i

  def self.call(kitchen:, files:)
    new(kitchen, files).import
  end

  def initialize(kitchen, files)
    @kitchen = kitchen
    @files = files
    @recipes_count = 0
    @ingredients_count = 0
    @quick_bites_imported = false
    @errors = []
  end

  def import
    zip_file = files.find { |f| File.extname(f.original_filename).casecmp('.zip').zero? }
    zip_file ? process_zip(zip_file) : files.each { |f| import_recipe_file(f, 'Miscellaneous') }
    kitchen.broadcast_update
    build_result
  end

  private

  attr_reader :kitchen, :files

  def build_result
    Result.new(recipes: @recipes_count, ingredients: @ingredients_count,
               quick_bites: @quick_bites_imported, errors: @errors)
  end

  def process_zip(zip_file)
    # Uploaded files may be Tempfile or StringIO — normalize to a stream
    Zip::InputStream.open(StringIO.new(zip_file.read)) do |zis|
      while (entry = zis.get_next_entry)
        # ZIP entries arrive as ASCII-8BIT; force UTF-8 for text processing
        process_zip_entry(entry.name.force_encoding('UTF-8'), zis.read.force_encoding('UTF-8'))
      end
    end
  end

  def process_zip_entry(name, content)
    basename = File.basename(name, '.*')
    ext = File.extname(name)

    if quick_bites?(basename, ext)
      import_quick_bites(content)
    elsif custom_ingredients?(name)
      import_ingredients(content, name)
    elsif recipe_file?(ext) && !directory_entry?(name)
      import_recipe_content(content, category_from_path(name), name)
    end
  end

  def quick_bites?(basename, ext)
    RECIPE_EXTENSIONS.include?(ext.downcase) && basename.match?(QUICK_BITES_PATTERN)
  end

  def custom_ingredients?(name)
    File.basename(name).casecmp('custom-ingredients.yaml').zero?
  end

  def recipe_file?(ext)
    RECIPE_EXTENSIONS.include?(ext.downcase)
  end

  def directory_entry?(name)
    name.end_with?('/')
  end

  def category_from_path(name)
    parts = name.split('/')
    parts.size > 1 ? parts[-2] : 'Miscellaneous'
  end

  def import_recipe_file(file, category_name)
    import_recipe_content(file.read, category_name, file.original_filename)
  end

  def import_recipe_content(content, category_name, filename)
    RecipeWriteService.create(markdown: content, kitchen: kitchen, category_name: category_name)
    @recipes_count += 1
  rescue StandardError => error
    @errors << "#{filename}: #{error.message}"
  end

  def import_quick_bites(content)
    kitchen.update!(quick_bites_content: content)
    @quick_bites_imported = true
  end

  def import_ingredients(content, filename)
    data = YAML.safe_load(content)
    data.each do |name, entry|
      upsert_catalog_entry(name, entry)
    end
  rescue StandardError => error
    @errors << "#{filename}: #{error.message}"
  end

  def upsert_catalog_entry(name, entry)
    record = IngredientCatalog.find_or_initialize_by(kitchen: kitchen, ingredient_name: name)
    record.assign_attributes(IngredientCatalog.attrs_from_yaml(entry))
    record.save!
    @ingredients_count += 1
  end
end
