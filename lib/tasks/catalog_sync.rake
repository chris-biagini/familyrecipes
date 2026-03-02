# frozen_string_literal: true

def sync_catalog_entry(name, entry)
  profile = IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name)
  profile.assign_attributes(IngredientCatalog.attrs_from_yaml(entry))

  return :created if profile.new_record? && profile.save!
  return :updated if profile.changed? && profile.save!

  :unchanged
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
