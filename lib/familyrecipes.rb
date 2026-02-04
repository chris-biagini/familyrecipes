# This file handles loading all required libraries and classes

# libraries

require 'fileutils'
require 'erb'
require 'redcarpet'
require 'digest'
require 'json'
require 'yaml'
require 'set'

# Shared utilities
module FamilyRecipes
  # Generate a URL-safe slug from a title string
  def self.slugify(title)
    title
      .unicode_normalize(:nfkd)
      .downcase
      .gsub(/\s+/, '-')
      .gsub(/[^a-z0-9\-]/, '')
  end
end

# my classes

require_relative 'familyrecipes/ingredient'
require_relative 'familyrecipes/step'
require_relative 'familyrecipes/recipe'
require_relative 'familyrecipes/quick_bite'
