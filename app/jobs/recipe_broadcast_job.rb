# frozen_string_literal: true

# Runs RecipeBroadcaster calls off the request thread via perform_later.
# Accepts only primitive/serializable arguments so ActiveJob can enqueue
# without serializing AR objects. Re-fetches records and sets tenant context.
#
# - RecipeWriteService: sole enqueuer
# - RecipeBroadcaster: does the actual Turbo Stream work
class RecipeBroadcastJob < ApplicationJob
  def perform(kitchen_id:, action:, recipe_title:, recipe_id: nil, parent_ids: [])
    kitchen = Kitchen.find(kitchen_id)
    recipe = kitchen.recipes.find_by(id: recipe_id)

    if action == 'destroy'
      RecipeBroadcaster.broadcast_destroy(kitchen:, recipe:, recipe_title:, parent_ids:)
    else
      RecipeBroadcaster.broadcast(kitchen:, action: action.to_sym, recipe_title:, recipe:)
    end
  end
end
