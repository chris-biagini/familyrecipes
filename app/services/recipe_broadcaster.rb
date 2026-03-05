# frozen_string_literal: true

# Handles targeted recipe-specific broadcasts that cannot be expressed as page
# morphs: delete notifications (recipe no longer exists) and rename redirects
# (recipe URL changed). All other recipe updates use Kitchen#broadcast_update
# for page-refresh morphs.
#
# - RecipeWriteService: sole caller
# - Turbo::StreamsChannel: transport layer for targeted stream pushes
class RecipeBroadcaster
  def self.notify_recipe_deleted(recipe, recipe_title:)
    Turbo::StreamsChannel.broadcast_replace_to(
      recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: }
    )
    Turbo::StreamsChannel.broadcast_append_to(
      recipe, 'content',
      target: 'notifications',
      partial: 'shared/toast',
      locals: { message: "#{recipe_title} was deleted" }
    )
  end

  def self.broadcast_rename(old_recipe, new_title:, redirect_path:)
    Turbo::StreamsChannel.broadcast_replace_to(
      old_recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: old_recipe.title,
                redirect_path:,
                redirect_title: new_title }
    )
  end
end
