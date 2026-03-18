# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/familyrecipes'

class SmartTagRegistryTest < Minitest::Test
  def test_lookup_known_tag
    entry = FamilyRecipes::SmartTagRegistry.lookup('vegetarian')

    assert_equal '🌿', entry[:emoji]
    assert_equal :green, entry[:color]
  end

  def test_lookup_crossout_tag
    entry = FamilyRecipes::SmartTagRegistry.lookup('gluten-free')

    assert_equal :crossout, entry[:style]
    assert_equal :amber, entry[:color]
  end

  def test_lookup_cuisine_tag
    entry = FamilyRecipes::SmartTagRegistry.lookup('thai')

    assert_equal '🇹🇭', entry[:emoji]
    assert_equal :cuisine, entry[:color]
  end

  def test_lookup_unknown_tag_returns_nil
    assert_nil FamilyRecipes::SmartTagRegistry.lookup('unknown-tag')
  end

  def test_tags_frozen
    assert_predicate FamilyRecipes::SmartTagRegistry::TAGS, :frozen?
  end

  def test_all_entries_have_required_keys
    FamilyRecipes::SmartTagRegistry::TAGS.each do |name, entry|
      assert entry.key?(:emoji), "#{name} missing :emoji"
      assert entry.key?(:color), "#{name} missing :color"
    end
  end
end
