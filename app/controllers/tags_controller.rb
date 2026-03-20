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
    tag_names = current_kitchen.tags.order(:name).pluck(:name)

    respond_to do |format|
      format.html { render partial: 'tags/content_frame', locals: { items: tag_names }, layout: false }
      format.json { render json: { items: tag_names.map { |name| { name: } } } }
    end
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
