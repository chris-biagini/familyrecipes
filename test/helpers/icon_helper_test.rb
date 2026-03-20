# frozen_string_literal: true

require 'test_helper'

class IconHelperTest < ActionView::TestCase
  test 'renders svg tag with default attributes' do
    result = icon(:edit, size: 12)

    assert_includes result, '<svg'
    assert_includes result, 'width="12"'
    assert_includes result, 'height="12"'
    assert_includes result, 'fill="none"'
    assert_includes result, 'stroke="currentColor"'
    assert_includes result, 'stroke-linecap="round"'
    assert_includes result, 'stroke-linejoin="round"'
    assert_includes result, 'aria-hidden="true"'
    assert_includes result, '</svg>'
  end

  test 'uses per-icon viewBox' do
    result = icon(:edit, size: 12)

    assert_includes result, 'viewBox="0 0 32 32"'
  end

  test 'uses per-icon stroke-width' do
    edit_result = icon(:edit, size: 12)
    search_result = icon(:search, size: 12)

    assert_includes edit_result, 'stroke-width="2.5"'
    assert_includes search_result, 'stroke-width="1.8"'
  end

  test 'size nil omits width and height' do
    result = icon(:search, size: nil)

    assert_not_includes result, ' width='
    assert_not_includes result, ' height='
  end

  test 'merges custom class' do
    result = icon(:search, size: nil, class: 'nav-icon')

    assert_includes result, 'class="nav-icon"'
  end

  test 'nil value removes default attribute' do
    result = icon(:apple, size: 14, 'aria-hidden': nil, 'aria-label': 'Has nutrition')

    assert_not_includes result, 'aria-hidden'
    assert_includes result, 'aria-label="Has nutrition"'
  end

  test 'caller attrs override per-icon defaults' do
    result = icon(:edit, size: 12, 'stroke-width': '4')

    assert_includes result, 'stroke-width="4"'
    assert_not_includes result, 'stroke-width="2.5"'
  end

  test 'escapes attribute values' do
    result = icon(:edit, size: 12, class: 'a"b')

    assert_includes result, 'class="a&quot;b"'
  end

  test 'raises ArgumentError for unknown icon' do
    assert_raises(ArgumentError) { icon(:nonexistent) }
  end

  test 'returns html safe string' do
    assert_predicate icon(:edit, size: 12), :html_safe?
  end

  test 'contains expected svg content for each icon' do
    IconHelper::ICONS.each_key do |name|
      result = icon(name, size: 12)

      assert_includes result, '<svg', "#{name} should render an svg tag"
      assert_includes result, '</svg>', "#{name} should close the svg tag"
    end
  end
end
