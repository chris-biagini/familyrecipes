# frozen_string_literal: true

# Processes uploaded files for import into a kitchen. Accepts ZIP archives
# (matching export format) or individual recipe files (.md, .txt, .text).
# Routes each file to the appropriate handler: RecipeWriteService for recipes,
# CatalogWriteService for ingredient catalog entries, direct assignment for
# Quick Bites.
#
# - RecipeWriteService: recipe upsert (create or overwrite by slug)
# - CatalogWriteService: ingredient catalog upsert by name
# - Kitchen: tenant container receiving imported data
# - ExportService: produces the ZIP format this service consumes
class ImportService
  Result = Data.define(:recipes, :ingredients, :quick_bites, :errors) do
    def self.empty
      new(recipes: 0, ingredients: 0, quick_bites: false, errors: [])
    end
  end

  def self.call(kitchen:, files:)
    new(kitchen, files).import
  end

  def initialize(kitchen, files)
    @kitchen = kitchen
    @files = files
  end

  def import
    Result.empty
  end

  private

  attr_reader :kitchen, :files
end
