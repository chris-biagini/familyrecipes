# frozen_string_literal: true

# Decomposes the monolithic meal_plans.state JSON column into four normalized
# tables: meal_plan_selections, on_hand_entries, custom_grocery_items, and
# cook_history_entries. Migrates existing JSON data via raw SQL, then drops
# the state and lock_version columns.
class DecomposeMealPlan < ActiveRecord::Migration[8.1]
  def up
    create_meal_plan_selections
    create_on_hand_entries
    create_custom_grocery_items
    create_cook_history_entries

    migrate_data

    remove_column :meal_plans, :state
    remove_column :meal_plans, :lock_version
  end

  def down
    add_column :meal_plans, :state, :json, default: {}, null: false
    add_column :meal_plans, :lock_version, :integer, default: 0, null: false

    reverse_migrate_data

    drop_table :cook_history_entries
    drop_table :custom_grocery_items
    drop_table :on_hand_entries
    drop_table :meal_plan_selections
  end

  private

  def create_meal_plan_selections
    create_table :meal_plan_selections do |t|
      t.integer :kitchen_id, null: false
      t.string :selectable_type, null: false
      t.string :selectable_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :meal_plan_selections, %i[kitchen_id selectable_type selectable_id],
              unique: true, name: 'idx_meal_plan_selections_unique'
  end

  def create_on_hand_entries
    create_table :on_hand_entries do |t|
      t.integer :kitchen_id, null: false
      t.string :ingredient_name, null: false, collation: 'NOCASE'
      t.date :confirmed_at, null: false
      t.float :interval
      t.float :ease
      t.date :depleted_at
      t.date :orphaned_at
      t.timestamps
    end
    add_index :on_hand_entries, %i[kitchen_id ingredient_name],
              unique: true, name: 'idx_on_hand_entries_unique'
  end

  def create_custom_grocery_items
    create_table :custom_grocery_items do |t|
      t.integer :kitchen_id, null: false
      t.string :name, null: false, collation: 'NOCASE'
      t.string :aisle, default: 'Miscellaneous', null: false
      t.date :on_hand_at
      t.date :last_used_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :custom_grocery_items, %i[kitchen_id name],
              unique: true, name: 'idx_custom_grocery_items_unique'
  end

  def create_cook_history_entries
    create_table :cook_history_entries do |t|
      t.integer :kitchen_id, null: false
      t.string :recipe_slug, null: false
      t.datetime :cooked_at, null: false
    end
    add_index :cook_history_entries, %i[kitchen_id recipe_slug cooked_at],
              name: 'idx_cook_history_entries_lookup'
  end

  def migrate_data
    rows = execute("SELECT kitchen_id, state FROM meal_plans").to_a
    rows.each { |row| migrate_row(row) }
  end

  def migrate_row(row)
    kitchen_id = row['kitchen_id']
    state = parse_state(row['state'])
    return if state.empty?

    migrate_selections(kitchen_id, state)
    migrate_on_hand(kitchen_id, state)
    migrate_custom_items(kitchen_id, state)
    migrate_cook_history(kitchen_id, state)
  end

  def parse_state(raw)
    return {} if raw.nil?

    raw.is_a?(String) ? JSON.parse(raw) : raw
  rescue JSON::ParserError
    {}
  end

  def migrate_selections(kitchen_id, state)
    now = Time.current.iso8601

    Array(state['selected_recipes']).each do |slug|
      execute(<<~SQL)
        INSERT OR IGNORE INTO meal_plan_selections (kitchen_id, selectable_type, selectable_id, created_at)
        VALUES (#{kitchen_id}, 'Recipe', #{quote(slug)}, #{quote(now)})
      SQL
    end

    Array(state['selected_quick_bites']).each do |id|
      execute(<<~SQL)
        INSERT OR IGNORE INTO meal_plan_selections (kitchen_id, selectable_type, selectable_id, created_at)
        VALUES (#{kitchen_id}, 'QuickBite', #{quote(id)}, #{quote(now)})
      SQL
    end
  end

  def migrate_on_hand(kitchen_id, state)
    on_hand = state['on_hand']
    return unless on_hand.is_a?(Hash)

    now = Time.current.iso8601
    on_hand.each do |name, entry|
      next unless entry.is_a?(Hash)

      confirmed_at = entry['confirmed_at'] || Date.current.iso8601
      interval = entry['interval']
      ease = entry['ease']
      depleted_at = entry['depleted_at']
      orphaned_at = entry['orphaned_at']

      execute(<<~SQL)
        INSERT OR IGNORE INTO on_hand_entries
          (kitchen_id, ingredient_name, confirmed_at, interval, ease, depleted_at, orphaned_at, created_at, updated_at)
        VALUES (#{kitchen_id}, #{quote(name)}, #{quote(confirmed_at)},
                #{interval ? interval : 'NULL'}, #{ease ? ease : 'NULL'},
                #{depleted_at ? quote(depleted_at) : 'NULL'},
                #{orphaned_at ? quote(orphaned_at) : 'NULL'},
                #{quote(now)}, #{quote(now)})
      SQL
    end
  end

  def migrate_custom_items(kitchen_id, state)
    custom = state['custom_items']
    return unless custom.is_a?(Hash)

    now = Time.current.iso8601
    custom.each do |name, entry|
      next unless entry.is_a?(Hash)

      aisle = entry['aisle'] || 'Miscellaneous'
      last_used_at = entry['last_used_at'] || Date.current.iso8601
      on_hand_at = entry['on_hand_at']

      execute(<<~SQL)
        INSERT OR IGNORE INTO custom_grocery_items
          (kitchen_id, name, aisle, on_hand_at, last_used_at, created_at)
        VALUES (#{kitchen_id}, #{quote(name)}, #{quote(aisle)},
                #{on_hand_at ? quote(on_hand_at) : 'NULL'},
                #{quote(last_used_at)}, #{quote(now)})
      SQL
    end
  end

  def migrate_cook_history(kitchen_id, state)
    history = state['cook_history']
    return unless history.is_a?(Array)

    history.each do |entry|
      next unless entry.is_a?(Hash) && entry['slug'] && entry['at']

      execute(<<~SQL)
        INSERT INTO cook_history_entries (kitchen_id, recipe_slug, cooked_at)
        VALUES (#{kitchen_id}, #{quote(entry['slug'])}, #{quote(entry['at'])})
      SQL
    end
  end

  def reverse_migrate_data
    execute("SELECT id, kitchen_id FROM meal_plans").to_a.each do |row|
      kitchen_id = row['kitchen_id']
      state = build_reverse_state(kitchen_id)
      execute("UPDATE meal_plans SET state = #{quote(state.to_json)} WHERE id = #{row['id']}")
    end
  end

  def build_reverse_state(kitchen_id)
    {
      'selected_recipes' => reverse_selections(kitchen_id, 'Recipe'),
      'selected_quick_bites' => reverse_selections(kitchen_id, 'QuickBite'),
      'on_hand' => reverse_on_hand(kitchen_id),
      'custom_items' => reverse_custom_items(kitchen_id),
      'cook_history' => reverse_cook_history(kitchen_id)
    }
  end

  def reverse_selections(kitchen_id, type)
    execute(<<~SQL).to_a.map { |r| r['selectable_id'] }
      SELECT selectable_id FROM meal_plan_selections
      WHERE kitchen_id = #{kitchen_id} AND selectable_type = #{quote(type)}
    SQL
  end

  def reverse_on_hand(kitchen_id)
    execute(<<~SQL).to_a.each_with_object({}) do |r, hash|
      SELECT ingredient_name, confirmed_at, interval, ease, depleted_at, orphaned_at
      FROM on_hand_entries WHERE kitchen_id = #{kitchen_id}
    SQL
      entry = { 'confirmed_at' => r['confirmed_at'], 'interval' => r['interval'], 'ease' => r['ease'] }
      entry['depleted_at'] = r['depleted_at'] if r['depleted_at']
      entry['orphaned_at'] = r['orphaned_at'] if r['orphaned_at']
      hash[r['ingredient_name']] = entry
    end
  end

  def reverse_custom_items(kitchen_id)
    execute(<<~SQL).to_a.each_with_object({}) do |r, hash|
      SELECT name, aisle, on_hand_at, last_used_at
      FROM custom_grocery_items WHERE kitchen_id = #{kitchen_id}
    SQL
      hash[r['name']] = { 'aisle' => r['aisle'], 'last_used_at' => r['last_used_at'], 'on_hand_at' => r['on_hand_at'] }
    end
  end

  def reverse_cook_history(kitchen_id)
    execute(<<~SQL).to_a.map { |r| { 'slug' => r['recipe_slug'], 'at' => r['cooked_at'] } }
      SELECT recipe_slug, cooked_at FROM cook_history_entries
      WHERE kitchen_id = #{kitchen_id}
    SQL
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
