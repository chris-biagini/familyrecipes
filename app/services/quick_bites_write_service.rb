# frozen_string_literal: true

# Orchestrates quick bites content updates. Dual entry: `update` accepts raw
# plaintext; `update_from_structure` accepts an IR hash and serializes via
# QuickBitesSerializer. Owns persistence to Kitchen#quick_bites_content and
# parse validation (returning warnings). Delegates post-write finalization
# to Kitchen.finalize_writes. Parallels RecipeWriteService — controllers
# call class methods, never inline post-save logic.
#
# - QuickBitesSerializer: IR hash → plaintext (update_from_structure path)
# - Kitchen#quick_bites_content: raw plaintext storage
# - FamilyRecipes.parse_quick_bites_content: parser returning warnings
# - Kitchen.finalize_writes: centralized post-write pipeline
class QuickBitesWriteService
  Result = Data.define(:warnings)

  def self.update(kitchen:, content:)
    new(kitchen:).update(content:)
  end

  def self.update_from_structure(kitchen:, structure:)
    content = FamilyRecipes::QuickBitesSerializer.serialize(structure)
    new(kitchen:).update(content:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(content:)
    stored = content.to_s.presence
    warnings = parse_warnings(stored)
    kitchen.update!(quick_bites_content: stored)
    finalize
    Result.new(warnings:)
  end

  private

  attr_reader :kitchen

  def parse_warnings(content)
    return [] unless content

    FamilyRecipes.parse_quick_bites_content(content).warnings
  end

  def finalize
    Kitchen.finalize_writes(kitchen)
  end
end
