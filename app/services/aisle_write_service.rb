# frozen_string_literal: true

# Placeholder — architectural header comment will be added in Task 4.
class AisleWriteService
  Result = Data.define(:success, :errors)

  def self.update_order(kitchen:, aisle_order:, renames:, deletes:)
    new(kitchen:).update_order(aisle_order:, renames:, deletes:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update_order(aisle_order:, renames:, deletes:)
    kitchen.aisle_order = aisle_order.to_s

    errors = validate_order
    return Result.new(success: false, errors:) if errors.any?

    kitchen.normalize_aisle_order!

    ActiveRecord::Base.transaction do
      cascade_renames(renames)
      cascade_deletes(deletes)
      kitchen.save!
    end

    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def validate_order
    items = kitchen.parsed_aisle_order
    errors = []
    errors << "Too many items (maximum #{Kitchen::MAX_AISLES})." if items.size > Kitchen::MAX_AISLES

    long = items.select { |name| name.size > Kitchen::MAX_AISLE_NAME_LENGTH }
    long.each { |name| errors << "\"#{name}\" is too long (maximum #{Kitchen::MAX_AISLE_NAME_LENGTH} characters)." }

    # Exact duplicates are silently normalized away; only flag mixed-case variants
    dupes = items.group_by(&:downcase).select { |_, v| v.uniq.size > 1 }.values.map(&:first)
    dupes.each { |name| errors << "\"#{name}\" appears more than once (case-insensitive)." }
    errors
  end

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
