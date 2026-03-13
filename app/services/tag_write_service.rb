# frozen_string_literal: true

# Handles bulk tag management operations (rename, delete) from the
# tag management dialog. Follows the same changeset pattern as
# CategoryWriteService — a single call processes all mutations.
#
# Collaborators:
# - Tag: the model being mutated
# - TagsController: thin controller that delegates here
# - Kitchen#broadcast_update: notifies clients after changes
class TagWriteService
  Result = Data.define(:success, :errors)

  def self.update(kitchen:, renames:, deletes:)
    errors = validate_renames(kitchen, renames)
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      apply_renames(kitchen, renames)
      apply_deletes(kitchen, deletes)
    end

    kitchen.broadcast_update
    Result.new(success: true, errors: [])
  end

  def self.validate_renames(kitchen, renames)
    existing = kitchen.tags.pluck(:name)
    renames.filter_map do |old_name, new_name|
      normalized = new_name.downcase
      "Tag '#{new_name}' already exists" if normalized != old_name && existing.include?(normalized)
    end
  end
  private_class_method :validate_renames

  def self.apply_renames(kitchen, renames)
    renames.each do |old_name, new_name|
      tag = kitchen.tags.find_by!(name: old_name)
      tag.update!(name: new_name.downcase)
    end
  end
  private_class_method :apply_renames

  def self.apply_deletes(kitchen, deletes)
    kitchen.tags.where(name: deletes).destroy_all if deletes.any?
  end
  private_class_method :apply_deletes
end
