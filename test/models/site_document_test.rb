# frozen_string_literal: true

require 'test_helper'

class SiteDocumentTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
  end

  test 'requires name' do
    doc = SiteDocument.new(content: 'hello', kitchen: @kitchen)

    assert_not doc.valid?
    assert_includes doc.errors[:name], "can't be blank"
  end

  test 'requires content' do
    doc = SiteDocument.new(name: 'test', kitchen: @kitchen)

    assert_not doc.valid?
    assert_includes doc.errors[:content], "can't be blank"
  end

  test 'enforces unique name per kitchen' do
    SiteDocument.create!(name: 'quick_bites', content: 'hello', kitchen: @kitchen)
    dup = SiteDocument.new(name: 'quick_bites', content: 'world', kitchen: @kitchen)

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end
end
