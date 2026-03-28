# frozen_string_literal: true

require 'test_helper'
require_relative '../../lib/profile_baseline'

class ProfileBaselineTest < ActiveSupport::TestCase
  setup do
    create_kitchen_and_user
    setup_test_category(name: 'Main Dishes')
    @recipe = create_recipe("# Test Recipe\n\n## Step 1\nMix ingredients.", category_name: 'Main Dishes')
    MealPlan.find_or_create_by!(kitchen: @kitchen)
  end

  test 'page_profiles returns timing and query data for key pages' do
    profiler = ProfileBaseline.new(@kitchen, @user)
    results = profiler.page_profiles

    assert_kind_of Array, results
    assert_operator results.size, :>=, 4, "Expected at least 4 pages profiled, got #{results.size}"

    results.each do |result|
      assert_predicate result[:name], :present?, 'Each result needs a page name'
      assert_kind_of Numeric, result[:time_ms], "#{result[:name]} time_ms should be numeric"
      assert_kind_of Integer, result[:queries], "#{result[:name]} queries should be integer"
      assert_kind_of Integer, result[:html_bytes], "#{result[:name]} html_bytes should be integer"
      assert_operator result[:queries], :>=, 0, "#{result[:name]} query count should be non-negative"
      assert_predicate result[:html_bytes], :positive?, "#{result[:name]} should return non-empty HTML"
    end
  end

  test 'asset_profiles returns bundle size data with gzipped sizes' do
    profiler = ProfileBaseline.new(@kitchen, @user)
    results = profiler.asset_profiles

    assert_kind_of Array, results

    results.each do |result|
      assert_predicate result[:name], :present?
      assert_kind_of Integer, result[:raw_bytes]
      assert_kind_of Integer, result[:gzipped_bytes]
      assert_operator result[:gzipped_bytes], :<=, result[:raw_bytes], "#{result[:name]} gzipped should be <= raw"
    end
  end
end
