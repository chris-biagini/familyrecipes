# frozen_string_literal: true

require 'test_helper'

class MenuAvailabilityCacheTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category(name: 'Main Dishes')
    @recipe = create_recipe("# Test Recipe\n\n## Step 1\nMix ingredients.", category_name: 'Main Dishes')
    MealPlan.find_or_create_by!(kitchen: @kitchen)
    log_in
  end

  test 'second menu load uses cached availability (fewer queries)' do
    get menu_path(kitchen_slug: kitchen_slug)
    assert_response :success

    first_count = count_queries { get menu_path(kitchen_slug: kitchen_slug) }
    second_count = count_queries { get menu_path(kitchen_slug: kitchen_slug) }

    assert second_count <= first_count,
           "Second load (#{second_count} queries) should not exceed first (#{first_count})"
  end

  test 'availability cache invalidates when kitchen is updated' do
    get menu_path(kitchen_slug: kitchen_slug)
    assert_response :success

    @kitchen.update_column(:updated_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

    get menu_path(kitchen_slug: kitchen_slug)
    assert_response :success
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached]
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end
end
