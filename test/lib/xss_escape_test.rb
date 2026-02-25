# frozen_string_literal: true

require 'test_helper'

class XssEscapeTest < ActiveSupport::TestCase
  test 'MARKDOWN renderer escapes raw script tags' do
    output = FamilyRecipes::Recipe::MARKDOWN.render('<script>alert("xss")</script>')

    assert_includes output, '&lt;script&gt;'
    assert_not_includes output, '<script>'
  end

  test 'MARKDOWN renderer preserves markdown-generated HTML' do
    output = FamilyRecipes::Recipe::MARKDOWN.render('**bold** and *italic*')

    assert_includes output, '<strong>bold</strong>'
    assert_includes output, '<em>italic</em>'
  end

  test 'MARKDOWN renderer escapes img onerror payload' do
    output = FamilyRecipes::Recipe::MARKDOWN.render('<img src=x onerror=alert(1)>')

    assert_not_includes output, '<img'
    assert_includes output, '&lt;img'
  end
end
