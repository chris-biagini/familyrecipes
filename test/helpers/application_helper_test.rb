# frozen_string_literal: true

require 'test_helper'

class ApplicationHelperTest < ActionView::TestCase
  test 'format_numeric returns integer string for whole float' do
    assert_equal '3', format_numeric(3.0)
  end

  test 'format_numeric returns float string for non-whole float' do
    assert_equal '1.5', format_numeric(1.5)
  end

  test 'format_numeric handles zero' do
    assert_equal '0', format_numeric(0.0)
  end

  test 'format_numeric handles integer input' do
    assert_equal '12', format_numeric(12)
  end

  test 'help_url prepends base URL to path' do
    assert_equal 'https://chris-biagini.github.io/familyrecipes/recipes/', help_url('/recipes/')
  end

  test 'help_url works with nested path' do
    assert_equal 'https://chris-biagini.github.io/familyrecipes/recipes/editing/', help_url('/recipes/editing/')
  end
end
