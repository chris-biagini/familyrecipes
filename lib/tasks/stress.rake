# frozen_string_literal: true

require_relative '../stress_data_generator'

namespace :profile do
  desc 'Generate stress test data (200 recipes, full grocery state, cook history)'
  task generate_stress_data: :environment do
    count = ENV.fetch('RECIPE_COUNT', 200).to_i
    puts "Generating stress data with #{count} recipes..."
    StressDataGenerator.new(recipe_count: count).generate!
  end
end
