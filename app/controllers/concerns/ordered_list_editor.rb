# frozen_string_literal: true

# Shared validation for ordered-list editor dialogs (aisles, categories).
# Validates item count and name length. Each including controller defines
# its own cascade and persistence logic.
#
# - GroceriesController: aisle ordering
# - CategoriesController: category ordering
module OrderedListEditor
  extend ActiveSupport::Concern

  private

  def validate_ordered_list(items, max_items:, max_name_length:)
    errors = []
    errors << "Too many items (maximum #{max_items})." if items.size > max_items

    long = items.select { |name| name.size > max_name_length }
    long.each { |name| errors << "\"#{name}\" is too long (maximum #{max_name_length} characters)." }
    errors
  end
end
