# frozen_string_literal: true

# Creates `quick_bites` and `quick_bite_ingredients` tables, migrates data from
# the Kitchen#quick_bites_content text blob, rewrites meal_plan_selections QB
# rows from slug IDs to integer PKs, and drops the text column.
#
# Inline parser avoids application code dependencies per project conventions.
class NormalizeQuickBites < ActiveRecord::Migration[8.0] # rubocop:disable Metrics/ClassLength
  def up
    create_quick_bites_table
    create_quick_bite_ingredients_table
    migrate_data
    remove_column :kitchens, :quick_bites_content, :text
  end

  def down
    add_column :kitchens, :quick_bites_content, :text
    reverse_data
    drop_table :quick_bite_ingredients
    drop_table :quick_bites
  end

  private

  def create_quick_bites_table
    create_table :quick_bites do |t|
      t.integer :kitchen_id, null: false
      t.integer :category_id, null: false
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :quick_bites, %i[kitchen_id category_id]
    add_index :quick_bites, %i[kitchen_id title], unique: true
  end

  def create_quick_bite_ingredients_table
    create_table :quick_bite_ingredients do |t|
      t.integer :quick_bite_id, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :quick_bite_ingredients, :quick_bite_id
  end

  def migrate_data
    execute(<<~SQL.squish).each { |row| migrate_kitchen(row['id'], row['quick_bites_content']) }
      SELECT id, quick_bites_content FROM kitchens
      WHERE quick_bites_content IS NOT NULL AND quick_bites_content != ''
    SQL
  end

  # Format: "## Subcategory\n- Title: Ing1, Ing2\n- SelfRef\n"
  def migrate_kitchen(kitchen_id, content)
    now = Time.current.iso8601
    current_subcategory = nil
    position = 0

    content.each_line do |raw_line|
      line = raw_line.strip
      if line.start_with?('## ')
        current_subcategory = line.delete_prefix('## ').strip
      elsif line.start_with?('- ') && current_subcategory
        position = migrate_entry(kitchen_id, current_subcategory, line, position, now)
      end
    end
  end

  def migrate_entry(kitchen_id, subcategory, line, position, now)
    title, rest = line.delete_prefix('- ').strip.split(':', 2).map(&:strip)
    rest = nil if rest&.empty?
    ingredients = rest ? rest.split(',').map(&:strip).reject(&:empty?) : [title]

    category_id = find_or_create_category(kitchen_id, subcategory, now)
    qb_id = insert_quick_bite(kitchen_id, category_id, title, position, now)
    insert_ingredients(qb_id, ingredients)
    rewrite_selection(kitchen_id, slugify(title), qb_id)
    position + 1
  end

  # Minimal slugify — matches FamilyRecipes.slugify for ASCII titles.
  def slugify(text)
    text.unicode_normalize(:nfkd)
        .encode('ASCII', replace: '')
        .downcase
        .gsub(/\s+/, '-')
        .gsub(/[^a-z0-9-]/, '')
        .gsub(/-{2,}/, '-')
        .sub(/^-|-$/, '')
  end

  def find_or_create_category(kitchen_id, name, now)
    slug = slugify(name)
    existing = execute(<<~SQL.squish).first
      SELECT id FROM categories
      WHERE kitchen_id = #{kitchen_id} AND slug = #{quote(slug)} LIMIT 1
    SQL
    return existing['id'] if existing

    max_pos = execute(<<~SQL.squish).first['mp'].to_i
      SELECT MAX(position) AS mp FROM categories WHERE kitchen_id = #{kitchen_id}
    SQL
    execute(<<~SQL.squish)
      INSERT INTO categories (kitchen_id, name, slug, position, created_at, updated_at)
      VALUES (#{kitchen_id}, #{quote(name)}, #{quote(slug)}, #{max_pos + 1}, #{quote(now)}, #{quote(now)})
    SQL
    last_insert_id
  end

  def insert_quick_bite(kitchen_id, category_id, title, position, now)
    execute(<<~SQL.squish)
      INSERT INTO quick_bites (kitchen_id, category_id, title, position, created_at, updated_at)
      VALUES (#{kitchen_id}, #{category_id}, #{quote(title)}, #{position}, #{quote(now)}, #{quote(now)})
    SQL
    last_insert_id
  end

  def insert_ingredients(qb_id, ingredients)
    now = Time.current.iso8601
    ingredients.each_with_index do |name, idx|
      execute(<<~SQL.squish)
        INSERT INTO quick_bite_ingredients (quick_bite_id, name, position, created_at, updated_at)
        VALUES (#{qb_id}, #{quote(name)}, #{idx}, #{quote(now)}, #{quote(now)})
      SQL
    end
  end

  def rewrite_selection(kitchen_id, old_slug_id, new_int_id)
    execute(<<~SQL.squish)
      UPDATE meal_plan_selections SET selectable_id = #{quote(new_int_id.to_s)}
      WHERE kitchen_id = #{kitchen_id}
      AND selectable_type = 'QuickBite' AND selectable_id = #{quote(old_slug_id)}
    SQL
  end

  def last_insert_id
    execute('SELECT last_insert_rowid() AS id').first['id']
  end

  def reverse_data
    execute('SELECT DISTINCT kitchen_id FROM quick_bites').each { |row| reverse_kitchen(row['kitchen_id']) }
  end

  def reverse_kitchen(kitchen_id)
    qbs = execute(<<~SQL.squish)
      SELECT qb.id, qb.title, qb.position, c.name AS category_name
      FROM quick_bites qb JOIN categories c ON c.id = qb.category_id
      WHERE qb.kitchen_id = #{kitchen_id} ORDER BY c.position, qb.position
    SQL

    lines = build_reverse_lines(kitchen_id, qbs)
    content = lines.join("\n").strip
    content = nil if content.empty?
    execute("UPDATE kitchens SET quick_bites_content = #{content ? quote(content) : 'NULL'} WHERE id = #{kitchen_id}")
  end

  def build_reverse_lines(kitchen_id, qbs)
    current_category = nil
    qbs.each_with_object([]) do |quick_bite, lines|
      if quick_bite['category_name'] != current_category
        lines << '' if current_category
        lines << "## #{quick_bite['category_name']}"
        current_category = quick_bite['category_name']
      end

      lines << reverse_entry_line(quick_bite)
      reverse_rewrite_selection(kitchen_id, quick_bite)
    end
  end

  def reverse_entry_line(quick_bite)
    ingredients = execute(<<~SQL.squish).pluck('name')
      SELECT name FROM quick_bite_ingredients
      WHERE quick_bite_id = #{quick_bite['id']} ORDER BY position
    SQL

    return "- #{quick_bite['title']}" if ingredients == [quick_bite['title']]

    "- #{quick_bite['title']}: #{ingredients.join(', ')}"
  end

  def reverse_rewrite_selection(kitchen_id, quick_bite)
    execute(<<~SQL.squish)
      UPDATE meal_plan_selections SET selectable_id = #{quote(slugify(quick_bite['title']))}
      WHERE kitchen_id = #{kitchen_id}
      AND selectable_type = 'QuickBite' AND selectable_id = #{quote(quick_bite['id'].to_s)}
    SQL
  end
end
