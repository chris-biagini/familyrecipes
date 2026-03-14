# frozen_string_literal: true

# Shared validation for rename hashes in ordered-list editors (aisles,
# categories). Checks that new names don't exceed a maximum length.
# Returns an array of error strings (empty if valid).
#
# Collaborators:
# - AisleWriteService, CategoryWriteService: include this module
module RenameValidation
  private

  def validate_renames(renames, max)
    return [] unless renames.is_a?(Hash) || renames.is_a?(ActionController::Parameters)

    renames.values
           .select { |name| name.size > max }
           .map { |name| "\"#{name}\" exceeds maximum length of #{max} characters." }
  end
end
