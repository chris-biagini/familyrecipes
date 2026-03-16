# frozen_string_literal: true

class MigrateQuickBitesHeaders < ActiveRecord::Migration[8.0]
  def up
    rows = select_all("SELECT id, quick_bites_content FROM kitchens WHERE quick_bites_content IS NOT NULL")
    rows.each do |row|
      converted = row["quick_bites_content"].gsub(/^([^#\-\n].+?):\s*$/m, '## \1')
      quoted = ActiveRecord::Base.connection.quote(converted)
      execute("UPDATE kitchens SET quick_bites_content = #{quoted} WHERE id = #{row['id']}")
    end
  end

  def down
    rows = select_all("SELECT id, quick_bites_content FROM kitchens WHERE quick_bites_content IS NOT NULL")
    rows.each do |row|
      reverted = row["quick_bites_content"].gsub(/^##\s+(.+?)$/m, '\1:')
      quoted = ActiveRecord::Base.connection.quote(reverted)
      execute("UPDATE kitchens SET quick_bites_content = #{quoted} WHERE id = #{row['id']}")
    end
  end
end
