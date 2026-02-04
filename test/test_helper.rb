# Test helper - loads the library and sets up test environment

require 'minitest/autorun'
require_relative '../lib/familyrecipes'

# Set template directory for tests that need it
FamilyRecipes.template_dir = File.join(File.dirname(__FILE__), '..', 'templates', 'web')
