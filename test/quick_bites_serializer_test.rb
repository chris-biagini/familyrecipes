# frozen_string_literal: true

require_relative 'test_helper'

class QuickBitesSerializerTest < Minitest::Test
  def parse_to_ir(content)
    result = Mirepoix.parse_quick_bites_content(content)
    Mirepoix::QuickBitesSerializer.to_ir(result.quick_bites)
  end

  def test_round_trip_preserves_content
    content = <<~TXT
      ## Snacks
      - Apples and Honey: Apples, Honey
      - Goldfish

      ## Breakfast
      - Cereal with Milk: Cereal, Milk
    TXT

    ir = parse_to_ir(content)
    serialized = Mirepoix::QuickBitesSerializer.serialize(ir)
    ir_again = parse_to_ir(serialized)

    assert_equal ir, ir_again
  end

  def test_item_without_ingredients_omits_colon
    ir = {
      categories: [
        {
          name: 'Snacks',
          items: [
            { name: 'Banana', ingredients: ['Banana'] }
          ]
        }
      ]
    }

    output = Mirepoix::QuickBitesSerializer.serialize(ir)

    assert_equal "## Snacks\n- Banana\n", output
  end

  def test_empty_categories_produces_empty_output
    ir = { categories: [] }

    output = Mirepoix::QuickBitesSerializer.serialize(ir)

    assert_equal '', output
  end

  def test_items_without_subcategory_header
    content = <<~TXT
      - Banana
      - Crackers and Cheese: Crackers, Cheese
    TXT

    ir = parse_to_ir(content)

    assert_equal 1, ir[:categories].size
    assert_equal 'Quick Bites', ir[:categories].first[:name]
    assert_equal 2, ir[:categories].first[:items].size
  end

  def test_serialize_multiple_categories_have_blank_line_between
    ir = {
      categories: [
        { name: 'Snacks', items: [{ name: 'Chips', ingredients: ['Chips'] }] },
        { name: 'Drinks', items: [{ name: 'Lemonade', ingredients: %w[Lemons Sugar Water] }] }
      ]
    }

    output = Mirepoix::QuickBitesSerializer.serialize(ir)

    assert_equal "## Snacks\n- Chips\n\n## Drinks\n- Lemonade: Lemons, Sugar, Water\n", output
  end

  def test_serialize_item_with_explicit_ingredients
    ir = {
      categories: [
        {
          name: 'Lunch',
          items: [
            { name: 'PB&J', ingredients: ['Peanut butter', 'Jelly', 'Bread'] }
          ]
        }
      ]
    }

    output = Mirepoix::QuickBitesSerializer.serialize(ir)

    assert_equal "## Lunch\n- PB&J: Peanut butter, Jelly, Bread\n", output
  end

  def test_to_ir_extracts_subcategory_name
    content = <<~TXT
      ## Kids' Lunches
      - RXBARs
    TXT

    ir = parse_to_ir(content)

    assert_equal "Kids' Lunches", ir[:categories].first[:name]
  end

  def test_to_ir_maps_item_fields
    content = <<~TXT
      ## Snacks
      - Trail Mix: Nuts, Raisins, Chocolate chips
    TXT

    ir = parse_to_ir(content)
    item = ir[:categories].first[:items].first

    assert_equal 'Trail Mix', item[:name]
    assert_equal ['Nuts', 'Raisins', 'Chocolate chips'], item[:ingredients]
  end
end
