# frozen_string_literal: true

# CRUD for recipes. Show is public; create/update/destroy require membership.
# Write actions validate Markdown, run MarkdownImporter (parser → DB), cascade
# cross-reference updates, recalculate nutrition, prune stale meal plan entries,
# and broadcast real-time updates via RecipeBroadcaster.
class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]

  rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record

  def show
    embedded_steps = { steps: %i[ingredients cross_references] }
    @recipe = current_kitchen.recipes
                             .includes(steps: [:ingredients,
                                               { cross_references: { target_recipe: embedded_steps } }])
                             .find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
  end

  def create
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)
    recipe.update!(edited_at: Time.current)

    RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :created, recipe_title: recipe.title, recipe: recipe)
    render json: { redirect_url: recipe_path(recipe.slug) }
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def update # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    old_title = @recipe.title
    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)

    updated_references = if old_title == recipe.title
                           []
                         else
                           CrossReferenceUpdater.rename_references(
                             old_title:, new_title: recipe.title, kitchen: current_kitchen
                           )
                         end

    if recipe.slug != @recipe.slug
      RecipeBroadcaster.broadcast_rename(@recipe, new_title: recipe.title, new_slug: recipe.slug)
      @recipe.destroy!
    end
    recipe.update!(edited_at: Time.current)
    Category.cleanup_orphans(current_kitchen)
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { plan.prune_checked_off }

    RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :updated, recipe_title: recipe.title, recipe: recipe)
    response_json = { redirect_url: recipe_path(recipe.slug) }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  def destroy
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
    parent_ids = @recipe.referencing_recipes.pluck(:id)

    RecipeBroadcaster.notify_recipe_deleted(@recipe, recipe_title: @recipe.title)
    @recipe.destroy!
    broadcast_to_referencing_recipes(parent_ids) if parent_ids.any?
    Category.cleanup_orphans(current_kitchen)
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { plan.prune_checked_off }

    RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :deleted,
                                recipe_title: @recipe.title)

    render json: { redirect_url: home_path }
  end

  private

  def broadcast_to_referencing_recipes(parent_ids)
    parents = current_kitchen.recipes.where(id: parent_ids).includes(RecipeBroadcaster::SHOW_INCLUDES)
    parents.find_each do |parent|
      Turbo::StreamsChannel.broadcast_replace_to(
        parent, 'content',
        target: 'recipe-content',
        partial: 'recipes/recipe_content',
        locals: { recipe: parent, nutrition: parent.nutrition_data }
      )
    end
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end
