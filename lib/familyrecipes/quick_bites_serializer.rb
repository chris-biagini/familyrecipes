# frozen_string_literal: true

module FamilyRecipes
  # Pure-function serializer that converts a Quick Bites IR hash to canonical
  # plaintext and vice versa. The inverse of parse_quick_bites_content — together
  # they form a lossless round-trip for editor save/load cycles. No ActiveSupport
  # dependencies; pure Ruby only.
  #
  # - FamilyRecipes.parse_quick_bites_content: parser (plaintext -> QuickBite[])
  # - QuickBitesWriteService: persistence orchestrator that will consume serialize output
  # - MenuController: editor UI that round-trips through to_ir/serialize
  module QuickBitesSerializer
    module_function

    def serialize(intermediate)
      intermediate[:categories]
        .map { |cat| serialize_category(cat) }
        .join("\n")
    end

    def to_ir(quick_bites)
      groups = quick_bites.group_by(&:category)

      categories = groups.map do |category, items|
        subcategory = category.split(': ', 2).last
        { name: subcategory, items: items.map { |qb| item_hash(qb) } }
      end

      { categories: categories }
    end

    def serialize_category(category)
      lines = category[:items].map { |item| serialize_item(item) }
      "## #{category[:name]}\n#{lines.join("\n")}\n"
    end

    def serialize_item(item)
      return "- #{item[:name]}" if self_referencing?(item)

      "- #{item[:name]}: #{item[:ingredients].join(', ')}"
    end

    def self_referencing?(item)
      item[:ingredients] == [item[:name]]
    end

    def item_hash(quick_bite)
      { name: quick_bite.title, ingredients: quick_bite.ingredients }
    end
  end
end
