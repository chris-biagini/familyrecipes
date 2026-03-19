# frozen_string_literal: true

# Bulk-recomputes nutrition_data for all recipes across all kitchens.
# Safe to run any time — idempotent, uses a shared resolver per kitchen
# to avoid redundant catalog queries. Intended as a deployment tool when
# migrations or catalog changes invalidate cached nutrition data.

namespace :nutrition do
  desc 'Recompute nutrition_data for all recipes in all kitchens'
  task recompute: :environment do
    Kitchen.find_each do |kitchen|
      ActsAsTenant.with_tenant(kitchen) do
        recipes = kitchen.recipes
        count = recipes.size

        if count.zero?
          puts "#{kitchen.name}: no recipes — skipping."
          next
        end

        resolver = IngredientCatalog.resolver_for(kitchen)
        recipes.find_each { |recipe| RecipeNutritionJob.perform_now(recipe, resolver:) }
        puts "#{kitchen.name}: recomputed nutrition for #{count} recipes."
      end
    end
  end
end
