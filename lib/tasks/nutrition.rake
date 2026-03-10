# frozen_string_literal: true

# One-shot backfill task — recalculates nutrition_data JSON for every recipe
# to populate fields added after initial import (e.g., total_weight_grams).
# Safe to run multiple times; each run overwrites the previous calculation.
namespace :nutrition do
  desc 'Recalculate nutrition_data for all recipes'
  task recalculate: :environment do
    count = 0
    # System-level operation — iterates all kitchens, not scoped to a request
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
