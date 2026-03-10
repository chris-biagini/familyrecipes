# frozen_string_literal: true

namespace :nutrition do
  desc 'Recalculate nutrition_data for all recipes'
  task recalculate: :environment do
    count = 0
    Kitchen.find_each do |kitchen|
      ActsAsTenant.with_tenant(kitchen) do
        Recipe.find_each do |recipe|
          RecipeNutritionJob.perform_now(recipe)
          count += 1
        end
      end
    end
    puts "Recalculated nutrition for #{count} recipes"
  end
end
