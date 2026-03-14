# frozen_string_literal: true

# Defense-in-depth validation for IR hashes received via `to_unsafe_h`.
# Downstream serializers cherry-pick known keys, but this concern rejects
# payloads with unexpected top-level keys at the controller boundary.
#
# - RecipesController: recipe structure (title, steps, etc.)
# - MenuController: quick bites structure (categories with items)
# - TagsController: tag renames hash (old_name -> new_name strings)
module StructureValidation
  extend ActiveSupport::Concern

  RECIPE_KEYS = %i[title description front_matter steps footer].to_set.freeze
  QUICK_BITES_KEYS = %i[categories].to_set.freeze

  MAX_TAG_NAME_LENGTH = 50

  private

  def validated_recipe_structure
    raw = params[:structure].to_unsafe_h.deep_symbolize_keys
    reject_unexpected_keys!(raw, RECIPE_KEYS)
    raw
  end

  def validated_quick_bites_structure
    raw = params[:structure].to_unsafe_h.deep_symbolize_keys
    reject_unexpected_keys!(raw, QUICK_BITES_KEYS)
    raw
  end

  def validated_tag_renames(renames_param)
    raw = renames_param.to_unsafe_h
    raw.each do |key, value|
      unless key.is_a?(String) && value.is_a?(String) &&
             key.size <= MAX_TAG_NAME_LENGTH && value.size <= MAX_TAG_NAME_LENGTH
        raise ActionController::BadRequest, 'Invalid tag rename entry'
      end
    end
    raw
  end

  def reject_unexpected_keys!(hash, allowed)
    unexpected = hash.keys.to_set - allowed
    raise ActionController::BadRequest, "Unexpected keys: #{unexpected.to_a.join(', ')}" if unexpected.any?
  end
end
