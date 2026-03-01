# frozen_string_literal: true

# Loads the FamilyRecipes domain/parser module at boot time. These classes live
# outside app/ and are not autoloaded by Zeitwerk — they're loaded once here and
# remain in memory. Changes to lib/familyrecipes/ require a server restart.
require_relative '../../lib/familyrecipes'
