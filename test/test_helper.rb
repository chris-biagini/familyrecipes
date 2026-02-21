# frozen_string_literal: true

# Test helper - loads the library and sets up test environment

ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'
require 'minitest/autorun'

# Set template directory for tests that need it
FamilyRecipes.template_dir = File.join(File.dirname(__FILE__), '..', 'templates', 'web')
