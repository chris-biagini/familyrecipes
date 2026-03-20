# frozen_string_literal: true

# View helpers for menu-related partials — Quick Bites category cards.
# Parallels RecipesHelper's ingredient_summary for recipe step cards.
#
# - MenuController: renders Quick Bites editor frame
# - _quickbites_category_card.html.erb: server-rendered category cards
module MenuHelper
  def item_summary(items)
    count = (items || []).size
    return '' if count.zero?

    pluralize(count, 'item')
  end

  def ingredients_display_text(item)
    return '' if item[:ingredients].blank?
    return '' if item[:ingredients].size == 1 && item[:ingredients].first == item[:name]

    item[:ingredients].join(', ')
  end
end
