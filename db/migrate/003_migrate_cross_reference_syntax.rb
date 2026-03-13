# frozen_string_literal: true

# Re-imports all recipes containing cross-references to rebuild step data
# after the syntax change from >>> to >. Also rewrites any remaining >>>
# syntax in markdown sources.
class MigrateCrossReferenceSyntax < ActiveRecord::Migration[8.0]
  def up
    Kitchen.find_each do |kitchen|
      ActsAsTenant.with_tenant(kitchen) do
        Recipe.where("markdown_source LIKE '%@[%'").find_each do |recipe|
          source = recipe.markdown_source.gsub('>>> @[', '> @[')
          MarkdownImporter.import(source, kitchen: kitchen, category: recipe.category)
        end
      end
    end
  end

  def down
    # No-op: re-importing with old parser would require reverting code first
  end
end
