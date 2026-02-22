# frozen_string_literal: true

require 'test_helper'

class SiteDocumentTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
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

  test 'content_for returns document content when found' do
    SiteDocument.create!(name: 'test_doc', content: 'hello world', kitchen: @kitchen)

    assert_equal 'hello world', SiteDocument.content_for('test_doc')
  end

  test 'content_for returns nil when document not found and no fallback' do
    assert_nil SiteDocument.content_for('nonexistent')
  end

  test 'content_for falls back to file when document not found' do
    path = Rails.root.join('db/seeds/resources/site-config.yaml')
    result = SiteDocument.content_for('nonexistent', fallback_path: path)

    assert result
    assert_includes result, 'title'
  end

  test 'content_for returns nil when document not found and fallback path missing' do
    assert_nil SiteDocument.content_for('nonexistent', fallback_path: '/nonexistent/file.yaml')
  end

  test 'content_for prefers document over fallback' do
    SiteDocument.create!(name: 'site_config', content: 'custom content', kitchen: @kitchen)
    path = Rails.root.join('db/seeds/resources/site-config.yaml')

    assert_equal 'custom content', SiteDocument.content_for('site_config', fallback_path: path)
  end
end
