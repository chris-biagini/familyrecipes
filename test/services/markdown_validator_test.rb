# frozen_string_literal: true

require_relative '../test_helper'

class MarkdownValidatorTest < ActiveSupport::TestCase
  test 'valid markdown returns no errors' do
    markdown = <<~MD
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix everything.
    MD

    errors = MarkdownValidator.validate(markdown)

    assert_empty errors
  end

  test 'missing title returns error' do
    errors = MarkdownValidator.validate('just some text')

    assert(errors.any? { |e| e.include?('title') || e.include?('header') })
  end

  test 'missing category returns error' do
    markdown = <<~MD
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix everything.
    MD

    errors = MarkdownValidator.validate(markdown)

    assert(errors.any? { |e| e.include?('Category') })
  end

  test 'empty markdown returns error' do
    errors = MarkdownValidator.validate('')

    assert_not_empty errors
  end

  test 'blank markdown returns error' do
    errors = MarkdownValidator.validate('   ')

    assert_not_empty errors
  end

  test 'markdown with no steps returns error' do
    markdown = <<~MD
      # Focaccia

      Category: Bread
    MD

    errors = MarkdownValidator.validate(markdown)

    assert(errors.any? { |e| e.include?('step') })
  end
end
