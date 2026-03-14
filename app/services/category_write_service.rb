# frozen_string_literal: true

# Orchestrates category ordering, renaming, and deletion. Cascade deletes reassign
# orphaned recipes to Miscellaneous. Called by CategoriesController for the Edit
# Categories dialog changeset.
#
# - Category: AR model with position column for homepage ordering
# - Kitchen#broadcast_update: page-refresh morph after successful writes
class CategoryWriteService
  Result = Data.define(:success, :errors)

  MAX_CATEGORIES = 50
  MAX_NAME_LENGTH = 50

  def self.update_order(kitchen:, names:, renames:, deletes:)
    new(kitchen:).update_order(names:, renames:, deletes:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update_order(names:, renames:, deletes:)
    errors = validate_order(names)
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      cascade_renames(renames)
      cascade_deletes(deletes)
      update_positions(names)
    end

    kitchen.broadcast_update
    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def validate_order(names)
    errors = []
    errors << "Too many items (maximum #{MAX_CATEGORIES})." if names.size > MAX_CATEGORIES

    long = names.select { |name| name.size > MAX_NAME_LENGTH }
    long.each { |name| errors << "\"#{name}\" is too long (maximum #{MAX_NAME_LENGTH} characters)." }

    dupes = names.group_by(&:downcase).select { |_, v| v.size > 1 }.values.map(&:first)
    dupes.each { |name| errors << "\"#{name}\" appears more than once (case-insensitive)." }
    errors
  end

  def cascade_renames(renames)
    return unless renames.is_a?(Hash) || renames.is_a?(ActionController::Parameters)

    renames.each_pair do |old_name, new_name|
      category = kitchen.categories.find_by!(slug: FamilyRecipes.slugify(old_name))
      category.update!(name: new_name, slug: FamilyRecipes.slugify(new_name))
    end
  end

  def cascade_deletes(deletes)
    deletes = Array(deletes)
    return if deletes.empty?

    misc = find_or_create_miscellaneous

    deletes.each do |name|
      category = kitchen.categories.find_by(slug: FamilyRecipes.slugify(name))
      next unless category

      category.recipes.update_all(category_id: misc.id) # rubocop:disable Rails/SkipsModelValidations
      category.destroy!
    end
  end

  def find_or_create_miscellaneous
    Category.miscellaneous(kitchen)
  end

  def update_positions(names)
    names.each_with_index do |name, index|
      kitchen.categories.where(slug: FamilyRecipes.slugify(name))
             .update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
