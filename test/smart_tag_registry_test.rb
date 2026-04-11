# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/mirepoix'

class SmartTagRegistryTest < Minitest::Test
  def test_lookup_known_tag
    entry = Mirepoix::SmartTagRegistry.lookup('vegetarian')

    assert_equal '🥕', entry[:emoji]
    assert_equal :green, entry[:color]
  end

  def test_lookup_crossout_tag
    entry = Mirepoix::SmartTagRegistry.lookup('gluten-free')

    assert_equal :crossout, entry[:style]
    assert_equal :amber, entry[:color]
  end

  def test_lookup_cuisine_tag
    entry = Mirepoix::SmartTagRegistry.lookup('thai')

    assert_equal '🇹🇭', entry[:emoji]
    assert_equal :cuisine, entry[:color]
  end

  def test_lookup_rose_tag
    entry = Mirepoix::SmartTagRegistry.lookup('grilled')

    assert_equal '🔥', entry[:emoji]
    assert_equal :rose, entry[:color]
  end

  def test_lookup_purple_tag
    entry = Mirepoix::SmartTagRegistry.lookup('thanksgiving')

    assert_equal '🦃', entry[:emoji]
    assert_equal :purple, entry[:color]
  end

  def test_lookup_unknown_tag_returns_nil
    assert_nil Mirepoix::SmartTagRegistry.lookup('unknown-tag')
  end

  def test_tags_frozen
    assert_predicate Mirepoix::SmartTagRegistry::TAGS, :frozen?
  end

  def test_all_entries_have_required_keys
    Mirepoix::SmartTagRegistry::TAGS.each do |name, entry|
      assert entry.key?(:emoji), "#{name} missing :emoji"
      assert entry.key?(:color), "#{name} missing :color"
    end
  end

  def test_all_colors_are_valid
    valid_colors = %i[green amber blue rose purple cuisine].freeze

    Mirepoix::SmartTagRegistry::TAGS.each do |name, entry|
      assert_includes valid_colors, entry[:color], "#{name} has invalid color: #{entry[:color]}"
    end
  end

  def test_attribution_tags_removed
    %w[julia-child marcella-hazan jacques-pepin jose-andres rick-bayless anthony-bourdain kenji grandma].each do |tag|
      assert_nil Mirepoix::SmartTagRegistry.lookup(tag), "#{tag} should not be in registry"
    end
  end
end
