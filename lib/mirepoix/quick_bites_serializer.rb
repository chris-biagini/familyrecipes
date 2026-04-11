# frozen_string_literal: true

module Mirepoix
  # Pure-function serializer that converts a Quick Bites IR hash to canonical
  # plaintext and vice versa. The inverse of parse_quick_bites_content — together
  # they form a lossless round-trip for editor save/load cycles. Also provides
  # `from_records` to build IR from AR-backed QuickBite/QuickBiteIngredient rows.
  #
  # - Mirepoix.parse_quick_bites_content: parser (plaintext -> QuickBite[])
  # - QuickBitesWriteService: persistence orchestrator that will consume serialize output
  # - MenuController: editor UI that round-trips through to_ir/serialize
  # - QuickBite / QuickBiteIngredient: AR models consumed by from_records
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

    def from_records(kitchen)
      grouped = kitchen.quick_bites.includes(:category, :quick_bite_ingredients)
                       .order('categories.position, quick_bites.position')
                       .group_by(&:category)

      categories = grouped.map do |category, qbs|
        {
          name: category.name,
          items: qbs.map { |qb| record_to_item(qb) }
        }
      end

      { categories: }
    end

    def record_to_item(quick_bite)
      { name: quick_bite.title, ingredients: quick_bite.quick_bite_ingredients.sort_by(&:position).map(&:name) }
    end
  end
end
