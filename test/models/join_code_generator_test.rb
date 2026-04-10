# frozen_string_literal: true

require 'test_helper'

class JoinCodeGeneratorTest < ActiveSupport::TestCase
  test 'word lists are loaded and frozen' do
    assert_predicate JoinCodeGenerator.descriptors, :frozen?
    assert_predicate JoinCodeGenerator.ingredients, :frozen?
    assert_predicate JoinCodeGenerator.dishes, :frozen?
  end

  test 'word lists are non-empty' do
    assert_operator JoinCodeGenerator.descriptors.size, :>=, 100
    assert_operator JoinCodeGenerator.ingredients.size, :>=, 400
    assert_operator JoinCodeGenerator.dishes.size, :>=, 100
  end

  test 'all words are lowercase ASCII' do
    all_words = JoinCodeGenerator.descriptors + JoinCodeGenerator.ingredients + JoinCodeGenerator.dishes

    all_words.each do |word|
      assert_match(/\A[a-z]+\z/, word, "Word '#{word}' contains non-ASCII or non-lowercase characters")
    end
  end

  test 'no duplicate words within or across lists' do
    all_words = JoinCodeGenerator.descriptors + JoinCodeGenerator.ingredients + JoinCodeGenerator.dishes

    assert_equal all_words.size, all_words.uniq.size, 'Duplicate words found in word lists'
  end

  test 'generate produces 4-word string' do
    code = JoinCodeGenerator.generate
    words = code.split

    assert_equal 4, words.size
  end

  test 'generate follows descriptor-ingredient-ingredient-dish format' do
    code = JoinCodeGenerator.generate
    words = code.split

    assert_includes JoinCodeGenerator.descriptors, words[0]
    assert_includes JoinCodeGenerator.ingredients, words[1]
    assert_includes JoinCodeGenerator.ingredients, words[2]
    assert_includes JoinCodeGenerator.dishes, words[3]
  end

  test 'two ingredients are different' do
    20.times do
      code = JoinCodeGenerator.generate
      words = code.split

      assert_not_equal words[1], words[2], "Duplicate ingredients in: #{code}"
    end
  end

  test 'generate produces different codes' do
    codes = Array.new(10) { JoinCodeGenerator.generate }

    assert_operator codes.uniq.size, :>, 1, 'All generated codes were identical'
  end
end
