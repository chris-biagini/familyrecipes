# frozen_string_literal: true

# Shared validation for ordered-list editors (aisles, categories). Provides
# order validation (count, name length, case-insensitive duplicate detection)
# and rename validation (max length for new names).
#
# Collaborators:
# - AisleWriteService, CategoryWriteService: include this module
module OrderedListValidation
  private

  def validate_order(items, max_items:, max_name_length:, exact_dupes: true)
    errors = []
    errors << "Too many items (maximum #{max_items})." if items.size > max_items

    long = items.select { |name| name.size > max_name_length }
    errors.concat(long.map { |name| "\"#{name}\" is too long (maximum #{max_name_length} characters)." })

    dupes = items.group_by(&:downcase)
                 .select { |_, v| exact_dupes ? v.size > 1 : v.uniq.size > 1 }
                 .values.map(&:first)
    errors.concat(dupes.map { |name| "\"#{name}\" appears more than once (case-insensitive)." })
    errors
  end

  def validate_renames(renames, max)
    return [] unless renames.is_a?(Hash) || renames.is_a?(ActionController::Parameters)

    renames.values
           .select { |name| name.size > max }
           .map { |name| "\"#{name}\" exceeds maximum length of #{max} characters." }
  end
end
