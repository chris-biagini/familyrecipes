# frozen_string_literal: true

# Thin controller for the tag management dialog. Provides content
# loading (list of tag names) and bulk update (renames + deletes).
# Delegates all business logic to TagWriteService.
#
# Collaborators:
# - TagWriteService: handles rename/delete changeset
# - Tag: queried for content listing
class TagsController < ApplicationController
  include StructureValidation

  before_action :require_membership

  def content
    items = current_kitchen.tags.order(:name).map { |t| { name: t.name } }
    render json: { items: }
  end

  def update_tags
    result = TagWriteService.update(
      kitchen: current_kitchen,
      renames: validated_tag_renames(params.fetch(:renames, {})),
      deletes: Array(params.fetch(:deletes, []))
    )

    if result.success
      render json: { success: true }
    else
      render json: { errors: result.errors }, status: :unprocessable_content
    end
  end
end
