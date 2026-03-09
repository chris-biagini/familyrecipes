# frozen_string_literal: true

# Processes uploaded files for import into a kitchen. Accepts ZIP archives
# (matching export format) or individual recipe files (.md, .txt, .text).
# Buffers ZIP entries by type, then processes in phased order: settings files
# first (aisle/category order), then catalog entries via CatalogWriteService,
# then quick bites, then recipes. This ordering ensures catalog data is in
# place before recipes compute nutrition.
#
# - CatalogWriteService: batch catalog upsert with aisle sync + nutrition recalc
# - RecipeWriteService: recipe upsert (create or overwrite by slug)
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
    zip_file ? import_zip(zip_file) : files.each { |f| import_recipe_file(f, 'Miscellaneous') }
    kitchen.broadcast_update
    build_result
  end

  private

  attr_reader :kitchen, :files

  def build_result
    Result.new(recipes: @recipes_count, ingredients: @ingredients_count,
               quick_bites: @quick_bites_imported, errors: @errors)
  end

  # --- ZIP buffering ---

  def import_zip(zip_file)
    buffered = buffer_zip_entries(zip_file)
    process_buffered_entries(buffered)
  end

  def buffer_zip_entries(zip_file)
    entries = { aisle_order: nil, category_order: nil, catalog: nil,
                quick_bites: nil, recipes: [] }

    Zip::InputStream.open(StringIO.new(zip_file.read)) do |zis|
      while (entry = zis.get_next_entry)
        name = entry.name.force_encoding('UTF-8')
        content = zis.read.force_encoding('UTF-8')
        classify_entry(entries, name, content)
      end
    end

    entries
  end

  def classify_entry(entries, name, content)
    basename = File.basename(name, '.*')
    ext = File.extname(name)

    if name == 'aisle-order.txt'
      entries[:aisle_order] = content
    elsif name == 'category-order.txt'
      entries[:category_order] = content
    elsif quick_bites?(basename, ext)
      entries[:quick_bites] = content
    elsif custom_ingredients?(name)
      entries[:catalog] = content
    elsif recipe_file?(ext) && !directory_entry?(name)
      entries[:recipes] << { content:, category: category_from_path(name), filename: name }
    end
  end

  # --- Phased processing ---

  def process_buffered_entries(entries)
    import_aisle_order(entries[:aisle_order])
    category_names = parse_category_order(entries[:category_order])
    import_catalog(entries[:catalog])
    import_quick_bites(entries[:quick_bites])
    entries[:recipes].each { |r| import_recipe_content(r[:content], r[:category], r[:filename]) }
    apply_category_order(category_names)
  end

  def import_aisle_order(content)
    return if content.blank?

    kitchen.update!(aisle_order: content.strip)
  end

  def parse_category_order(content)
    return [] if content.blank?

    content.lines.map(&:strip).reject(&:empty?)
  end

  def import_catalog(content)
    return if content.blank?

    data = YAML.safe_load(content)
    result = CatalogWriteService.bulk_import(kitchen:, entries_hash: data)
    @ingredients_count = result.persisted_count
    @errors.concat(result.errors)
  rescue StandardError => error
    @errors << "custom-ingredients.yaml: #{error.message}"
  end

  def import_quick_bites(content)
    return if content.blank?

    kitchen.update!(quick_bites_content: content)
    @quick_bites_imported = true
  end

  def import_recipe_content(content, category_name, filename)
    RecipeWriteService.create(markdown: content, kitchen:, category_name:)
    @recipes_count += 1
  rescue StandardError => error
    @errors << "#{filename}: #{error.message}"
  end

  def apply_category_order(category_names)
    return if category_names.empty?

    category_names.each_with_index do |name, index|
      kitchen.categories.where(slug: FamilyRecipes.slugify(name)).update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # --- Classification helpers ---

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

  # --- Non-ZIP import (individual files) ---

  def import_recipe_file(file, category_name)
    import_recipe_content(file.read.force_encoding('UTF-8'), category_name, file.original_filename)
  end
end
