# frozen_string_literal: true

# Rewrites cross-reference syntax from >>> to > in stored markdown sources.
# Uses raw SQL — migrations must never call application code (models, services,
# jobs) because they may depend on schema that doesn't exist yet.
class MigrateCrossReferenceSyntax < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE recipes
      SET markdown_source = REPLACE(markdown_source, '>>> @[', '> @['),
          updated_at = CURRENT_TIMESTAMP
      WHERE markdown_source LIKE '%>>> @[%'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE recipes
      SET markdown_source = REPLACE(markdown_source, '> @[', '>>> @['),
          updated_at = CURRENT_TIMESTAMP
      WHERE markdown_source LIKE '%> @[%'
    SQL
  end
end
