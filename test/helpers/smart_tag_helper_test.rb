# frozen_string_literal: true

require 'test_helper'

class SmartTagHelperTest < ActionView::TestCase
  include SmartTagHelper

  setup do
    @kitchen = Kitchen.new(decorate_tags: true)
  end

  test 'returns color class and emoji data for known tag' do
    attrs = smart_tag_pill_attrs('vegetarian', kitchen: @kitchen)

    assert_includes attrs[:class], 'tag-pill--green'
    assert_equal '🌿', attrs[:data][:smart_emoji]
  end

  test 'returns crossout class for crossout tag' do
    attrs = smart_tag_pill_attrs('gluten-free', kitchen: @kitchen)

    assert_includes attrs[:class], 'tag-pill--amber'
    assert_includes attrs[:class], 'tag-pill--crossout'
  end

  test 'returns empty hash for unknown tag' do
    attrs = smart_tag_pill_attrs('random-tag', kitchen: @kitchen)

    assert_empty(attrs)
  end

  test 'returns empty hash when decorations disabled' do
    @kitchen.decorate_tags = false
    attrs = smart_tag_pill_attrs('vegetarian', kitchen: @kitchen)

    assert_empty(attrs)
  end
end
