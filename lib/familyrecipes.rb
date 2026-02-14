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
  # Configuration constants
  CONFIG = {
    quick_bites_filename: 'Quick Bites.txt',
    quick_bites_category: 'Quick Bites',
    templates: {
      recipe: 'recipe-template.html.erb',
      homepage: 'homepage-template.html.erb',
      index: 'index-template.html.erb',
      groceries: 'groceries-template.html.erb'
    }
  }.freeze

  # Default template directory (can be overridden)
  @template_dir = nil

  class << self
    attr_accessor :template_dir
  end

  # Render a partial template with local variables
  # Usage: FamilyRecipes.render_partial('head', title: 'My Page')
  def self.render_partial(name, locals = {})
    raise "template_dir not set" unless @template_dir

    partial_path = File.join(@template_dir, "_#{name}.html.erb")
    partial_content = File.read(partial_path)
    ERB.new(partial_content, trim_mode: '-').result_with_hash(locals)
  end

  # Render a template and write to output file (only if content changed)
  # Usage: FamilyRecipes.render_template(:homepage, output_path, locals)
  def self.render_template(template_key, output_path, locals = {})
    raise "template_dir not set" unless @template_dir

    template_name = CONFIG[:templates][template_key]
    raise "Unknown template: #{template_key}" unless template_name

    template_path = File.join(@template_dir, template_name)
    erb_template = ERB.new(File.read(template_path), trim_mode: '-')

    FileUtils.mkdir_p(File.dirname(output_path))
    write_file_if_changed(output_path, erb_template.result_with_hash(locals))
  end

  # Generate a URL-safe slug from a title string
  def self.slugify(title)
    title
      .unicode_normalize(:nfkd)
      .downcase
      .gsub(/\s+/, '-')
      .gsub(/[^a-z0-9\-]/, '')
  end

  # Parse grocery-info.yaml into structured data
  # Items can be simple strings or hashes with 'name' and 'aliases' keys
  def self.parse_grocery_info(yaml_path)
    raw = YAML.safe_load_file(yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    aisles = {}

    raw.each do |aisle, items|
      aisles[aisle] = items.map do |item|
        if item.is_a?(Hash)
          name = item['name'].chomp('*')
          aliases = item['aliases'] || []
          staple = item['name'].end_with?('*')
        else
          name = item.chomp('*')
          aliases = []
          staple = item.end_with?('*')
        end
        { name: name, aliases: aliases, staple: staple }
      end
    end

    aisles
  end

  # Build a reverse lookup map: alias -> canonical name
  def self.build_alias_map(grocery_aisles)
    alias_map = {}

    grocery_aisles.each do |aisle, items|
      items.each do |item|
        canonical = item[:name]

        item[:aliases].each do |al|
          alias_map[al] = canonical
        end

        Ingredient.singularize(canonical).each do |singular|
          alias_map[singular] = canonical unless singular == canonical
        end

        item[:aliases].each do |al|
          Ingredient.singularize(al).each do |singular|
            alias_map[singular] = canonical unless singular == al
          end
        end
      end
    end

    alias_map
  end

  # Build set of all known ingredient names (canonical + aliases)
  def self.build_known_ingredients(grocery_aisles, alias_map)
    known = Set.new

    grocery_aisles.each do |aisle, items|
      items.each do |item|
        known << item[:name]
        known.merge(item[:aliases])
      end
    end

    known.merge(alias_map.keys)
    known
  end

  # Write file only if content has changed
  def self.write_file_if_changed(path, content)
    if File.exist?(path)
      return if File.read(path) == content
    end

    File.write(path, content)
    puts "Updated: #{path}"
  end
end

# my classes

require_relative 'familyrecipes/ingredient'
require_relative 'familyrecipes/ingredient_parser'
require_relative 'familyrecipes/line_classifier'
require_relative 'familyrecipes/recipe_builder'
require_relative 'familyrecipes/step'
require_relative 'familyrecipes/recipe'
require_relative 'familyrecipes/quick_bite'
require_relative 'familyrecipes/site_generator'
