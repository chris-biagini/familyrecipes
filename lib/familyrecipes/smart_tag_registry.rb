# frozen_string_literal: true

# Curated smart tag definitions — maps tag names to visual decorations
# (emoji, color group, optional crossout style). Purely presentational;
# tags not in this registry render as neutral pills.
#
# Collaborators:
# - SmartTagHelper: reads this to build CSS classes + data attributes
# - search_overlay_controller.js / tag_input_controller.js: consume JSON
#   version embedded in the layout
# - base.css: defines the .tag-pill--{color} and .tag-pill--crossout classes

module FamilyRecipes
  module SmartTagRegistry # rubocop:disable Metrics/ModuleLength
    TAGS = {
      # Green — plant-based dietary
      'vegetarian' => { emoji: '🌿', color: :green },
      'vegan' => { emoji: '🌱', color: :green },

      # Amber — dietary restrictions
      'gluten-free' => { emoji: '🌾', color: :amber, style: :crossout },
      'grain-free' => { emoji: '🌾', color: :amber, style: :crossout },
      'dairy-free' => { emoji: '🥛', color: :amber, style: :crossout },
      'nut-free' => { emoji: '🥜', color: :amber, style: :crossout },
      'peanut-free' => { emoji: '🥜', color: :amber, style: :crossout },
      'tree-nut-free' => { emoji: '🌰', color: :amber, style: :crossout },
      'egg-free' => { emoji: '🥚', color: :amber, style: :crossout },
      'soy-free' => { emoji: '🫘', color: :amber, style: :crossout },
      'sesame-free' => { emoji: '🫘', color: :amber, style: :crossout },
      'shellfish-free' => { emoji: '🦐', color: :amber, style: :crossout },
      'fish-free' => { emoji: '🐟', color: :amber, style: :crossout },
      'sugar-free' => { emoji: '🍬', color: :amber, style: :crossout },
      'alcohol-free' => { emoji: '🍷', color: :amber, style: :crossout },
      'nightshade-free' => { emoji: '🍆', color: :amber, style: :crossout },
      'corn-free' => { emoji: '🌽', color: :amber, style: :crossout },
      'fodmap-free' => { emoji: '🫃', color: :amber, style: :crossout },
      'kosher' => { emoji: '✡️', color: :amber },
      'halal' => { emoji: '☪️', color: :amber },
      'whole30' => { emoji: '🔢', color: :amber },
      'paleo' => { emoji: '🦴', color: :amber },
      'keto' => { emoji: '🥑', color: :amber },
      'low-carb' => { emoji: '📉', color: :amber },
      'low-sodium' => { emoji: '🧂', color: :amber, style: :crossout },
      'low-fodmap' => { emoji: '🫃', color: :amber },
      'aip' => { emoji: '🛡️', color: :amber },

      # Blue — effort/style
      'weeknight' => { emoji: '⏱️', color: :blue },
      'easy' => { emoji: '👌', color: :blue },
      'quick' => { emoji: '⚡', color: :blue },
      'one-pot' => { emoji: '🍳', color: :blue },
      'make-ahead' => { emoji: '📦', color: :blue },

      # Purple — attribution/special
      'julia-child' => { emoji: '🕵️‍♀️', color: :purple },
      'marcella-hazan' => { emoji: '🍅', color: :purple },
      'jacques-pepin' => { emoji: '🐓', color: :purple },
      'jose-andres' => { emoji: '🥘', color: :purple },
      'rick-bayless' => { emoji: '🌮', color: :purple },
      'anthony-bourdain' => { emoji: '🚬', color: :purple },
      'kenji' => { emoji: '🔬', color: :purple },
      'grandma' => { emoji: '💛', color: :purple },
      'holiday' => { emoji: '🎉', color: :purple },
      'comfort-food' => { emoji: '🛋️', color: :purple },

      # Cuisine — flag emoji, shared terracotta color

      # Americas
      'american' => { emoji: '🇺🇸', color: :cuisine },
      'mexican' => { emoji: '🇲🇽', color: :cuisine },
      'brazilian' => { emoji: '🇧🇷', color: :cuisine },
      'peruvian' => { emoji: '🇵🇪', color: :cuisine },
      'argentine' => { emoji: '🇦🇷', color: :cuisine },
      'colombian' => { emoji: '🇨🇴', color: :cuisine },
      'cuban' => { emoji: '🇨🇺', color: :cuisine },
      'jamaican' => { emoji: '🇯🇲', color: :cuisine },
      'haitian' => { emoji: '🇭🇹', color: :cuisine },
      'trinidadian' => { emoji: '🇹🇹', color: :cuisine },
      'puerto-rican' => { emoji: '🇵🇷', color: :cuisine },
      'salvadoran' => { emoji: '🇸🇻', color: :cuisine },
      'guatemalan' => { emoji: '🇬🇹', color: :cuisine },
      'venezuelan' => { emoji: '🇻🇪', color: :cuisine },
      'chilean' => { emoji: '🇨🇱', color: :cuisine },
      'ecuadorian' => { emoji: '🇪🇨', color: :cuisine },

      # Europe
      'french' => { emoji: '🇫🇷', color: :cuisine },
      'italian' => { emoji: '🇮🇹', color: :cuisine },
      'spanish' => { emoji: '🇪🇸', color: :cuisine },
      'portuguese' => { emoji: '🇵🇹', color: :cuisine },
      'greek' => { emoji: '🇬🇷', color: :cuisine },
      'german' => { emoji: '🇩🇪', color: :cuisine },
      'british' => { emoji: '🇬🇧', color: :cuisine },
      'irish' => { emoji: '🇮🇪', color: :cuisine },
      'polish' => { emoji: '🇵🇱', color: :cuisine },
      'hungarian' => { emoji: '🇭🇺', color: :cuisine },
      'swedish' => { emoji: '🇸🇪', color: :cuisine },
      'russian' => { emoji: '🇷🇺', color: :cuisine },
      'ukrainian' => { emoji: '🇺🇦', color: :cuisine },
      'romanian' => { emoji: '🇷🇴', color: :cuisine },
      'czech' => { emoji: '🇨🇿', color: :cuisine },
      'austrian' => { emoji: '🇦🇹', color: :cuisine },
      'swiss' => { emoji: '🇨🇭', color: :cuisine },
      'dutch' => { emoji: '🇳🇱', color: :cuisine },
      'belgian' => { emoji: '🇧🇪', color: :cuisine },
      'croatian' => { emoji: '🇭🇷', color: :cuisine },
      'serbian' => { emoji: '🇷🇸', color: :cuisine },

      # East & Southeast Asia
      'chinese' => { emoji: '🇨🇳', color: :cuisine },
      'japanese' => { emoji: '🇯🇵', color: :cuisine },
      'korean' => { emoji: '🇰🇷', color: :cuisine },
      'thai' => { emoji: '🇹🇭', color: :cuisine },
      'vietnamese' => { emoji: '🇻🇳', color: :cuisine },
      'filipino' => { emoji: '🇵🇭', color: :cuisine },
      'indonesian' => { emoji: '🇮🇩', color: :cuisine },
      'malaysian' => { emoji: '🇲🇾', color: :cuisine },
      'cambodian' => { emoji: '🇰🇭', color: :cuisine },
      'burmese' => { emoji: '🇲🇲', color: :cuisine },
      'taiwanese' => { emoji: '🇹🇼', color: :cuisine },

      # South Asia
      'indian' => { emoji: '🇮🇳', color: :cuisine },
      'pakistani' => { emoji: '🇵🇰', color: :cuisine },
      'sri-lankan' => { emoji: '🇱🇰', color: :cuisine },
      'bangladeshi' => { emoji: '🇧🇩', color: :cuisine },
      'nepali' => { emoji: '🇳🇵', color: :cuisine },
      'afghan' => { emoji: '🇦🇫', color: :cuisine },

      # Middle East & Central Asia
      'lebanese' => { emoji: '🇱🇧', color: :cuisine },
      'turkish' => { emoji: '🇹🇷', color: :cuisine },
      'iranian' => { emoji: '🇮🇷', color: :cuisine },
      'persian' => { emoji: '🇮🇷', color: :cuisine },
      'israeli' => { emoji: '🇮🇱', color: :cuisine },
      'iraqi' => { emoji: '🇮🇶', color: :cuisine },
      'syrian' => { emoji: '🇸🇾', color: :cuisine },
      'georgian' => { emoji: '🇬🇪', color: :cuisine },
      'uzbek' => { emoji: '🇺🇿', color: :cuisine },
      'yemeni' => { emoji: '🇾🇪', color: :cuisine },

      # Africa
      'ethiopian' => { emoji: '🇪🇹', color: :cuisine },
      'eritrean' => { emoji: '🇪🇷', color: :cuisine },
      'moroccan' => { emoji: '🇲🇦', color: :cuisine },
      'tunisian' => { emoji: '🇹🇳', color: :cuisine },
      'egyptian' => { emoji: '🇪🇬', color: :cuisine },
      'nigerian' => { emoji: '🇳🇬', color: :cuisine },
      'ghanaian' => { emoji: '🇬🇭', color: :cuisine },
      'senegalese' => { emoji: '🇸🇳', color: :cuisine },
      'somali' => { emoji: '🇸🇴', color: :cuisine },
      'south-african' => { emoji: '🇿🇦', color: :cuisine },
      'kenyan' => { emoji: '🇰🇪', color: :cuisine },

      # Oceania
      'australian' => { emoji: '🇦🇺', color: :cuisine },
      'new-zealand' => { emoji: '🇳🇿', color: :cuisine },
      'hawaiian' => { emoji: '🌺', color: :cuisine }
    }.freeze

    def self.lookup(tag)
      TAGS[tag]
    end
  end
end
