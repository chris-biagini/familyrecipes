# frozen_string_literal: true

# Orchestrates all aisle mutations: reorder, rename, delete (with cascade to
# IngredientCatalog rows), and new-aisle sync. Single owner of Kitchen#aisle_order
# writes — CatalogWriteService delegates here for aisle sync after catalog saves.
#
# - Kitchen#aisle_order: newline-delimited string of user-ordered aisle names
# - IngredientCatalog: cascade target for rename/delete operations
# - Kitchen#broadcast_update: notifies clients after successful order changes
# - CatalogWriteService: calls sync_new_aisles after catalog writes
class AisleWriteService
  include OrderedListValidation

  Result = Data.define(:success, :errors)

  def self.update_order(kitchen:, aisle_order:, renames:, deletes:)
    new(kitchen:).update_order(aisle_order:, renames:, deletes:)
  end

  def self.sync_new_aisles(kitchen:, aisles:)
    new(kitchen:).sync_new_aisles(aisles:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update_order(aisle_order:, renames:, deletes:)
    kitchen.aisle_order = aisle_order.to_s

    # Exact duplicates are silently normalized away; only flag mixed-case variants
    errors = validate_order(kitchen.parsed_aisle_order,
                            max_items: Kitchen::MAX_AISLES,
                            max_name_length: Kitchen::MAX_AISLE_NAME_LENGTH,
                            exact_dupes: false) +
             validate_renames(renames, Kitchen::MAX_AISLE_NAME_LENGTH)
    return Result.new(success: false, errors:) if errors.any?

    kitchen.normalize_aisle_order!

    ActiveRecord::Base.transaction do
      cascade_renames(renames)
      cascade_deletes(deletes)
      kitchen.save!
    end

    kitchen.broadcast_update
    Result.new(success: true, errors: [])
  end

  def sync_new_aisles(aisles:)
    return if aisles.empty?

    kitchen.reload
    current = kitchen.aisle_order.to_s.split("\n").reject(&:empty?)
    current.concat(aisles)
    kitchen.update!(aisle_order: current.uniq(&:downcase).join("\n"))
  end

  private

  attr_reader :kitchen

  def cascade_renames(renames)
    return unless renames.is_a?(Hash) || renames.is_a?(ActionController::Parameters)

    renames.each_pair do |old_name, new_name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', old_name)
             .update_all(aisle: new_name) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def cascade_deletes(deletes)
    return unless deletes.is_a?(Array)

    deletes.each do |name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', name)
             .update_all(aisle: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
