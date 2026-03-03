# frozen_string_literal: true

require 'test_helper'

class RecipesHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    setup_test_kitchen
  end

  test 'format_makes returns formatted string with whole quantity' do
    recipe = Recipe.new(makes_quantity: 30.0, makes_unit_noun: 'cookies')

    assert_equal '30 cookies', format_makes(recipe)
  end

  test 'format_makes returns formatted string with decimal quantity' do
    recipe = Recipe.new(makes_quantity: 1.5, makes_unit_noun: 'loaves')

    assert_equal '1.5 loaves', format_makes(recipe)
  end

  test 'format_makes returns nil when makes_quantity is nil' do
    recipe = Recipe.new(makes_quantity: nil)

    assert_nil format_makes(recipe)
  end
end
