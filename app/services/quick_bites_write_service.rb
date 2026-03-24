# frozen_string_literal: true

# Orchestrates quick bites updates. Dual entry: `update` accepts raw plaintext
# (parses to IR then saves via AR); `update_from_structure` accepts an IR hash
# and persists directly to QuickBite/QuickBiteIngredient records. Replaces all
# existing QBs on each save (full replacement, not incremental diff).
#
# - FamilyRecipes.parse_quick_bites_content: plaintext -> value objects (editor path)
# - FamilyRecipes::QuickBitesSerializer: value objects -> IR (editor path)
# - Category.find_or_create_for: category resolution
# - Kitchen.finalize_writes: centralized post-write pipeline
class QuickBitesWriteService
  Result = Data.define(:warnings)

  def self.update(kitchen:, content:)
    new(kitchen:).update(content:)
  end

  def self.update_from_structure(kitchen:, structure:)
    new(kitchen:).update_from_structure(structure:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(content:)
    stored = content.to_s.presence
    return clear_all if stored.nil?

    result = FamilyRecipes.parse_quick_bites_content(stored)
    ir = FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)
    persist_structure(ir)
    finalize
    Result.new(warnings: result.warnings)
  end

  def update_from_structure(structure:)
    persist_structure(structure)
    finalize
    Result.new(warnings: [])
  end

  private

  attr_reader :kitchen

  def clear_all
    kitchen.quick_bites.destroy_all
    finalize
    Result.new(warnings: [])
  end

  def persist_structure(structure)
    kitchen.quick_bites.destroy_all
    position = [0]

    structure[:categories].each do |cat_data|
      persist_category(cat_data, position)
    end
  end

  def persist_category(cat_data, position)
    category = Category.find_or_create_for(kitchen, cat_data[:name])

    cat_data[:items].each do |item|
      create_quick_bite(item, category:, position: position[0])
      position[0] += 1
    end
  end

  def create_quick_bite(item, category:, position:)
    qb = kitchen.quick_bites.create!(title: item[:name], category:, position:)
    item[:ingredients].each_with_index do |name, idx|
      qb.quick_bite_ingredients.create!(name:, position: idx)
    end
  end

  def finalize
    Kitchen.finalize_writes(kitchen)
  end
end
