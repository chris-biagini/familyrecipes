# frozen_string_literal: true

# Orchestrates all aisle mutations: reorder, rename, delete (with cascade to
# IngredientCatalog rows), and new-aisle sync. Extends ListWriteService for
# the shared validate → transaction → finalize skeleton.
#
# - Kitchen#aisle_order: newline-delimited string of user-ordered aisle names
# - IngredientCatalog: cascade target for rename/delete operations
# - CatalogWriteService: calls sync_new_aisles after catalog writes
# - ListWriteService: template method base class
class AisleWriteService < ListWriteService
  def self.sync_new_aisles(kitchen:, aisles:)
    new(kitchen:).sync_new_aisles(aisles:)
  end

  def sync_new_aisles(aisles:)
    return if aisles.empty?

    kitchen.reload
    current = kitchen.aisle_order.to_s.split("\n").reject(&:empty?)
    current.concat(aisles)
    kitchen.update!(aisle_order: current.uniq(&:downcase).join("\n"))
  end

  private

  # Exact duplicates are silently normalized away; only flag mixed-case variants
  def validate_changeset(renames:, aisle_order:, **)
    kitchen.aisle_order = aisle_order.to_s

    validate_order(kitchen.parsed_aisle_order,
                   max_items: Kitchen::MAX_AISLES,
                   max_name_length: Kitchen::MAX_AISLE_NAME_LENGTH,
                   exact_dupes: false) +
      validate_renames_length(renames, Kitchen::MAX_AISLE_NAME_LENGTH)
  end

  def apply_renames(renames)
    renames.each_pair do |old_name, new_name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', old_name)
             .update_all(aisle: new_name) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def apply_deletes(deletes)
    deletes.each do |name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', name)
             .update_all(aisle: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def apply_ordering(aisle_order:, **)
    kitchen.normalize_aisle_order!
    kitchen.save!
  end
end
