# frozen_string_literal: true

# Builds an in-memory ZIP archive of all kitchen data: aisle and category
# ordering, custom ingredient catalog entries, Quick Bites, and recipes
# organized by category. The ZIP is returned as a binary string suitable
# for streaming to a client.
#
# - ExportsController: sole caller (planned)
# - IngredientCatalog: custom entries exported as seed-compatible YAML
# - ImportService: consumes the ZIP format this service produces
# - Kitchen: tenant container providing recipes, quick_bites_content, slug
class ExportService
  def self.call(kitchen:)
    new(kitchen).build_zip
  end

  def self.filename(kitchen:)
    "#{kitchen.slug}-#{Date.current.iso8601}.zip"
  end

  def initialize(kitchen)
    @kitchen = kitchen
  end

  def build_zip
    buffer = Zip::OutputStream.write_buffer do |zos|
      add_aisle_order(zos)
      add_category_order(zos)
      add_custom_ingredients(zos)
      add_quick_bites(zos)
      add_recipes(zos)
    end
    buffer.string
  end

  private

  def add_recipes(zos)
    @kitchen.recipes.includes(:category).find_each do |recipe|
      zos.put_next_entry("#{recipe.category.name}/#{recipe.title}.md")
      zos.write(recipe.markdown_source)
    end
  end

  def add_quick_bites(zos)
    return if @kitchen.quick_bites_content.blank?

    zos.put_next_entry('quick-bites.txt')
    zos.write(@kitchen.quick_bites_content)
  end

  def add_aisle_order(zos)
    return if @kitchen.aisle_order.blank?

    zos.put_next_entry('aisle-order.txt')
    zos.write(@kitchen.aisle_order)
  end

  def add_category_order(zos)
    names = @kitchen.categories.ordered.pluck(:name)
    return if names.empty?

    zos.put_next_entry('category-order.txt')
    zos.write(names.join("\n"))
  end

  def add_custom_ingredients(zos)
    entries = IngredientCatalog.for_kitchen(@kitchen).order(:ingredient_name)
    return if entries.none?

    zos.put_next_entry('custom-ingredients.yaml')
    zos.write(catalog_to_yaml(entries))
  end

  def catalog_to_yaml(entries)
    hash = entries.each_with_object({}) do |entry, acc|
      acc[entry.ingredient_name] = entry_to_hash(entry)
    end
    hash.to_yaml
  end

  def entry_to_hash(entry)
    h = {}
    h['aisle'] = entry.aisle if entry.aisle.present?
    h['aliases'] = entry.aliases if entry.aliases.present?
    add_nutrients(h, entry)
    add_density(h, entry)
    h['portions'] = float_portions(entry.portions) if entry.portions.present?
    h['sources'] = entry.sources if entry.sources.present?
    h
  end

  def add_nutrients(hash, entry)
    nutrients = nutrient_values(entry)
    return if nutrients.empty?

    nutrients['basis_grams'] = entry.basis_grams.to_f
    hash['nutrients'] = nutrients
  end

  def add_density(hash, entry)
    return if entry.density_grams.blank?

    hash['density'] = {
      'grams' => entry.density_grams.to_f,
      'volume' => entry.density_volume.to_f,
      'unit' => entry.density_unit
    }
  end

  def float_portions(portions)
    portions.transform_values(&:to_f)
  end

  def nutrient_values(entry)
    IngredientCatalog::NUTRIENT_COLUMNS.each_with_object({}) do |col, acc|
      value = entry.public_send(col)
      acc[col.to_s] = value.to_f if value.present?
    end
  end
end
