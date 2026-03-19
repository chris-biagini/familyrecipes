# frozen_string_literal: true

# Orchestrates category ordering, renaming, and deletion. Cascade deletes
# reassign orphaned recipes to Miscellaneous. Extends ListWriteService for
# the shared validate → transaction → finalize skeleton.
#
# - Category: AR model with position column for homepage ordering
# - ListWriteService: template method base class
class CategoryWriteService < ListWriteService
  MAX_ITEMS = 50
  MAX_NAME_LENGTH = 50

  private

  def validate_changeset(renames:, names:, **)
    validate_order(names, max_items: MAX_ITEMS, max_name_length: MAX_NAME_LENGTH) +
      validate_renames_length(renames, MAX_NAME_LENGTH)
  end

  def apply_renames(renames)
    renames.each_pair do |old_name, new_name|
      category = kitchen.categories.find_by!(slug: FamilyRecipes.slugify(old_name))
      category.update!(name: new_name, slug: FamilyRecipes.slugify(new_name))
    end
  end

  def apply_deletes(deletes)
    return if deletes.empty?

    misc = Category.miscellaneous(kitchen)

    deletes.each do |name|
      category = kitchen.categories.find_by(slug: FamilyRecipes.slugify(name))
      next unless category

      category.recipes.update_all(category_id: misc.id) # rubocop:disable Rails/SkipsModelValidations
      category.destroy!
    end
  end

  def apply_ordering(names:, **)
    names.each_with_index do |name, index|
      kitchen.categories.where(slug: FamilyRecipes.slugify(name))
             .update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
