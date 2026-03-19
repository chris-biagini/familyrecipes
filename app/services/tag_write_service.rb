# frozen_string_literal: true

# Handles bulk tag management operations (rename, delete) from the tag
# management dialog. Extends ListWriteService for the shared validate →
# transaction → finalize skeleton. No ordering — tags sort alphabetically.
#
# - Tag: the model being mutated
# - TagsController: thin controller that delegates here
# - ListWriteService: template method base class
class TagWriteService < ListWriteService
  private

  def validate_changeset(renames:, **)
    existing = kitchen.tags.pluck(:name)
    renames.filter_map do |old_name, new_name|
      normalized = new_name.downcase
      "Tag '#{new_name}' already exists" if normalized != old_name && existing.include?(normalized)
    end
  end

  def apply_renames(renames)
    renames.each do |old_name, new_name|
      tag = kitchen.tags.find_by!(name: old_name)
      tag.update!(name: new_name.downcase)
    end
  end

  def apply_deletes(deletes)
    kitchen.tags.where(name: deletes).destroy_all if deletes.any?
  end
end
