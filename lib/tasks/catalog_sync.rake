# frozen_string_literal: true

def sync_catalog_entry(name, entry)
  profile = IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name)
  profile.assign_attributes(catalog_attrs(entry))

  return :created if profile.new_record? && profile.save!
  return :updated if profile.changed? && profile.save!

  :unchanged
end

def catalog_attrs(entry) # rubocop:disable Metrics/MethodLength
  attrs = { aisle: entry['aisle'] }

  if (nutrients = entry['nutrients'])
    attrs.merge!(
      basis_grams: nutrients['basis_grams'],
      calories: nutrients['calories'],
      fat: nutrients['fat'],
      saturated_fat: nutrients['saturated_fat'],
      trans_fat: nutrients['trans_fat'],
      cholesterol: nutrients['cholesterol'],
      sodium: nutrients['sodium'],
      carbs: nutrients['carbs'],
      fiber: nutrients['fiber'],
      total_sugars: nutrients['total_sugars'],
      added_sugars: nutrients['added_sugars'],
      protein: nutrients['protein']
    )
  end

  if (density = entry['density'])
    attrs.merge!(
      density_grams: density['grams'],
      density_volume: density['volume'],
      density_unit: density['unit']
    )
  end

  attrs[:portions] = entry['portions'] || {}
  attrs[:sources] = entry['sources'] || []

  attrs
end

namespace :catalog do
  desc 'Sync ingredient catalog from YAML seed file into global IngredientCatalog rows'
  task sync: :environment do
    catalog_path = Rails.root.join('db/seeds/resources/ingredient-catalog.yaml')

    unless catalog_path.exist?
      puts 'ingredient-catalog.yaml not found — skipping catalog sync.'
      next
    end

    catalog_data = YAML.safe_load_file(catalog_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    counts = catalog_data.map { |name, entry| sync_catalog_entry(name, entry) }.tally

    created = counts.fetch(:created, 0)
    updated = counts.fetch(:updated, 0)
    unchanged = counts.fetch(:unchanged, 0)

    puts "Catalog sync complete: #{created} created, #{updated} updated, #{unchanged} unchanged."
  end
end
