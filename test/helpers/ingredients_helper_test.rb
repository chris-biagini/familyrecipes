# frozen_string_literal: true

require 'test_helper'

class IngredientsHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen_id: nil).delete_all
  end

  test 'format_nutrient_value omits trailing zeros' do
    assert_equal '110', format_nutrient_value(110.0)
    assert_equal '0.5', format_nutrient_value(0.5)
    assert_equal '0', format_nutrient_value(0.0)
  end
end
