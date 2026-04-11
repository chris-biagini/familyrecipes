# frozen_string_literal: true

# Bridges SmartTagRegistry to views — returns CSS classes and data attributes
# for tag pills based on the curated registry. Returns empty hash for unknown
# tags or when decorations are disabled.
#
# Collaborators:
# - Mirepoix::SmartTagRegistry: the curated tag definitions
# - Kitchen#decorate_tags: per-kitchen toggle
# - _recipe_content.html.erb: server-rendered tag pills (recipe detail)
# - _recipe_listings.html.erb: filter pills and card tags (homepage)
module SmartTagHelper
  SMART_TAGS_JSON = Mirepoix::SmartTagRegistry::TAGS.to_json.freeze

  def smart_tags_json
    SMART_TAGS_JSON
  end

  def smart_tag_pill_attrs(tag_name, kitchen: current_kitchen)
    return {} unless kitchen.decorate_tags

    entry = Mirepoix::SmartTagRegistry.lookup(tag_name)
    return {} unless entry

    classes = ["tag-pill--#{entry[:color]}"]
    classes << 'tag-pill--crossout' if entry[:style] == :crossout

    { class: classes, data: { smart_emoji: entry[:emoji] } }
  end
end
