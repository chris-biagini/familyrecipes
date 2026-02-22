# frozen_string_literal: true

require 'test_helper'

class SiteDocumentTest < ActiveSupport::TestCase
  test 'requires name' do
    doc = SiteDocument.new(content: 'hello')

    assert_not doc.valid?
    assert_includes doc.errors[:name], "can't be blank"
  end

  test 'requires content' do
    doc = SiteDocument.new(name: 'test')

    assert_not doc.valid?
    assert_includes doc.errors[:content], "can't be blank"
  end

  test 'enforces unique name' do
    SiteDocument.create!(name: 'quick_bites', content: 'hello')
    dup = SiteDocument.new(name: 'quick_bites', content: 'world')

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end
end
