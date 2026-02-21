# frozen_string_literal: true

# Watch recipe markdown files and regenerate on changes.
# Only active in development — production uses pre-built static files.
return unless Rails.env.development?

Rails.application.config.after_initialize do
  file_watcher = ActiveSupport::FileUpdateChecker.new([], { Rails.root.join('recipes').to_s => ['md'] }) do
    Rails.logger.info 'Recipe files changed — regenerating static site...'
    RecipeFinder.reset_cache!
    RecipeRenderer.reset_cache!
    system('bin/generate', exception: true)
    Rails.logger.info 'Static site regenerated.'
  end

  ActiveSupport::Reloader.to_prepare do
    file_watcher.execute_if_updated
  end
end
