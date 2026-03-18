# frozen_string_literal: true

# Curated smart tag definitions — maps tag names to visual decorations
# (emoji, color group, optional crossout style). Purely presentational;
# tags not in this registry render as neutral pills.
#
# Collaborators:
# - SmartTagHelper: reads this to build CSS classes + data attributes
# - search_overlay_controller.js / tag_input_controller.js: consume JSON
#   version embedded in the layout
# - style.css: defines the .tag-pill--{color} and .tag-pill--crossout classes

module FamilyRecipes
  module SmartTagRegistry
    TAGS = {
      # Green — plant-based dietary
      'vegetarian' => { emoji: '🌿', color: :green },
      'vegan' => { emoji: '🌱', color: :green },

      # Amber — dietary restrictions
      'gluten-free' => { emoji: '🌾', color: :amber, style: :crossout },
      'grain-free' => { emoji: '🌾', color: :amber, style: :crossout },
      'dairy-free' => { emoji: '🥛', color: :amber, style: :crossout },
      'nut-free' => { emoji: '🥜', color: :amber, style: :crossout },
      'egg-free' => { emoji: '🥚', color: :amber, style: :crossout },
      'soy-free' => { emoji: '🫘', color: :amber, style: :crossout },
      'kosher' => { emoji: '✡️',  color: :amber },
      'halal' => { emoji: '☪️', color: :amber },

      # Blue — effort/style
      'weeknight' => { emoji: '⏱️', color: :blue },
      'easy' => { emoji: '👌', color: :blue },
      'quick' => { emoji: '⚡', color: :blue },
      'one-pot' => { emoji: '🍳', color: :blue },
      'make-ahead' => { emoji: '📦', color: :blue },

      # Purple — attribution/special
      'julia-child' => { emoji: '👩‍🍳', color: :purple },
      'kenji' => { emoji: '🔬', color: :purple },
      'grandma' => { emoji: '💛', color: :purple },
      'holiday' => { emoji: '🎉', color: :purple },
      'comfort-food' => { emoji: '🛋️', color: :purple },

      # Cuisine — flag emoji, shared terracotta color
      'american' => { emoji: '🇺🇸', color: :cuisine },
      'french' => { emoji: '🇫🇷', color: :cuisine },
      'thai' => { emoji: '🇹🇭', color: :cuisine },
      'italian' => { emoji: '🇮🇹', color: :cuisine },
      'mexican' => { emoji: '🇲🇽', color: :cuisine },
      'japanese' => { emoji: '🇯🇵', color: :cuisine },
      'indian' => { emoji: '🇮🇳', color: :cuisine },
      'chinese' => { emoji: '🇨🇳', color: :cuisine },
      'korean' => { emoji: '🇰🇷', color: :cuisine },
      'greek' => { emoji: '🇬🇷', color: :cuisine },
      'ethiopian' => { emoji: '🇪🇹', color: :cuisine },
      'lebanese' => { emoji: '🇱🇧', color: :cuisine }
    }.freeze

    def self.lookup(tag)
      TAGS[tag]
    end
  end
end
