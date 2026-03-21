# frozen_string_literal: true

require 'test_helper'

class MealPlanTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    MealPlan.where(kitchen: @kitchen).delete_all
  end

  def reconcile_plan!(plan, now: Date.current)
    resolver = IngredientCatalog.resolver_for(@kitchen)
    visible = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan, resolver:).visible_names
    plan.reconcile!(visible_names: visible, resolver:, now:)
  end

  test 'belongs to kitchen' do
    list = MealPlan.create!(kitchen: @kitchen)

    assert_equal @kitchen, list.kitchen
  end

  test 'enforces one list per kitchen' do
    MealPlan.create!(kitchen: @kitchen)
    duplicate = MealPlan.new(kitchen: @kitchen)

    assert_not_predicate duplicate, :valid?
  end

  test 'defaults to version 0 and empty state' do
    list = MealPlan.create!(kitchen: @kitchen)

    assert_equal 0, list.lock_version
    assert_empty list.state
  end

  test 'on_hand defaults to empty hash' do
    list = MealPlan.create!(kitchen: @kitchen)

    assert_empty list.on_hand
  end

  test 'ensure_state_keys initializes on_hand as hash not array' do
    list = MealPlan.create!(kitchen: @kitchen)
    list.apply_action('custom_items', item: 'test', action: 'add')
    list.reload

    assert_instance_of Hash, list.state['on_hand']
    assert_instance_of Array, list.state['custom_items']
  end

  test 'for_kitchen finds or creates' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_predicate list, :persisted?
    assert_equal @kitchen, list.kitchen

    assert_equal list, MealPlan.for_kitchen(@kitchen)
  end

  test 'apply_action adds recipe to selected_recipes' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)

    assert_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action removes recipe from selected_recipes' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: false)

    assert_not_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action adds quick bite to selected_quick_bites' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)

    assert_includes list.state['selected_quick_bites'], 'nachos'
  end

  test 'apply_action adds custom item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    assert_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action removes custom item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('custom_items', item: 'birthday candles', action: 'remove')

    assert_not_includes list.state['custom_items'], 'birthday candles'
  end

  test 'raises on unknown action types' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_raises(ArgumentError) { list.apply_action('bogus', foo: 'bar') }
  end

  test 'with_optimistic_retry retries on StaleObjectError' do
    list = MealPlan.for_kitchen(@kitchen)
    attempts = 0

    list.with_optimistic_retry do
      attempts += 1
      raise ActiveRecord::StaleObjectError, list if attempts == 1
    end

    assert_equal 2, attempts
  end

  test 'with_optimistic_retry raises after max attempts' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_raises(ActiveRecord::StaleObjectError) do
      list.with_optimistic_retry(max_attempts: 2) do
        raise ActiveRecord::StaleObjectError, list
      end
    end
  end

  # --- reconcile! ---

  test 'reconcile! expires orphaned on_hand entries preserving interval' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Phantom' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 28 }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert plan.on_hand.key?('Phantom'), 'Orphaned entry should persist with sentinel date'
    assert_equal '1970-01-01', plan.on_hand['Phantom']['confirmed_at']
    assert_equal 28, plan.on_hand['Phantom']['interval'], 'Learned interval should be preserved'
    assert_empty plan.effective_on_hand, 'Orphaned entry should not appear in effective_on_hand'
  end

  test 'reconcile! preserves on_hand entries in visible names' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 14 },
      'Phantom' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert plan.on_hand.key?('Flour')
    assert_equal '1970-01-01', plan.on_hand['Phantom']['confirmed_at'],
                 'Orphaned entry should be expired, not deleted'
  end

  test 'reconcile! preserves custom items in on_hand' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
    plan.state['on_hand'] = {
      'birthday candles' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert plan.on_hand.key?('birthday candles')
  end

  test 'reconcile! preserves custom items case-insensitively' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
    plan.state['on_hand'] = {
      'birthday candles' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert plan.on_hand.key?('Birthday Candles'), 'Key re-canonicalized to match custom item casing'
  end

  test 'expired entries in visible names stay in on_hand but not in effective_on_hand' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    md = "# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n"
    MarkdownImporter.import(md, kitchen: @kitchen, category: @category)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-01-01', 'interval' => 7 }
    }
    plan.save!

    assert plan.on_hand.key?('Flour'), 'Expired entry stays in raw on_hand'
    assert_not plan.effective_on_hand(now: Date.new(2026, 3, 21)).key?('Flour'),
               'Expired entry should not appear in effective_on_hand'
  end

  test 'reconcile! fixes orphaned null intervals' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    md = "# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n"
    MarkdownImporter.import(md, kitchen: @kitchen, category: @category)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert_equal 7, plan.on_hand['Flour']['interval'],
                 'Null interval should be converted to starting interval when item is not in custom_items'
  end

  test 'reconcile! re-canonicalizes on_hand keys when catalog changes' do
    create_catalog_entry('Flour', aisle: 'Baking')
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    md = "# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n"
    MarkdownImporter.import(md, kitchen: @kitchen, category: @category)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
    plan.state['on_hand'] = {
      'flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 28 }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert plan.on_hand.key?('Flour'), 'Key should be re-canonicalized to catalog name'
    assert_not plan.on_hand.key?('flour'), 'Old key should be removed'
    assert_equal 28, plan.on_hand['Flour']['interval'], 'Interval should be preserved'
  end

  test 'pruned item reappearing grows by ease on re-confirmation' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    md = "# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n"
    MarkdownImporter.import(md, kitchen: @kitchen, category: @category)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '1970-01-01', 'interval' => 28, 'ease' => 2.0 }
    }
    plan.save!

    plan.apply_action('check', item: 'Flour', checked: true, now: Date.new(2026, 3, 21))

    assert_in_delta 56.0, plan.on_hand['Flour']['interval'], 0.1,
                    'Re-confirming a pruned item: 28 * 2.0 = 56'
    assert_in_delta 2.1, plan.on_hand['Flour']['ease']
    assert_equal '2026-03-21', plan.on_hand['Flour']['confirmed_at']
  end

  test 'reconcile! merge prefers fresh entry over sentinel orphan' do
    create_catalog_entry('Flour', aisle: 'Baking')
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    md = "# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n"
    MarkdownImporter.import(md, kitchen: @kitchen, category: @category)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
    plan.state['on_hand'] = {
      'flour' => { 'confirmed_at' => '1970-01-01', 'interval' => 28 },
      'Flour' => { 'confirmed_at' => '2026-03-21', 'interval' => 7 }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert plan.on_hand.key?('Flour'), 'Should keep canonical key'
    assert_not plan.on_hand.key?('flour'), 'Should remove old key'
    assert_equal '2026-03-21', plan.on_hand['Flour']['confirmed_at'],
                 'Should prefer fresh (non-sentinel) entry over orphaned one'
    assert_equal 7, plan.on_hand['Flour']['interval']
  end

  test 'reconcile! sets orphaned_at when expiring entries' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Phantom' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 28 }
    }
    plan.save!

    today = Date.new(2026, 3, 21)
    reconcile_plan!(plan, now: today)
    plan.reload

    assert_equal '1970-01-01', plan.on_hand['Phantom']['confirmed_at']
    assert_equal today.iso8601, plan.on_hand['Phantom']['orphaned_at'],
                 'orphaned_at should be set when entry is first orphaned'
  end

  test 'reconcile! purges orphaned entries older than ORPHAN_RETENTION days' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Ancient' => { 'confirmed_at' => '1970-01-01', 'interval' => 14,
                     'orphaned_at' => '2025-06-01' },
      'Recent' => { 'confirmed_at' => '1970-01-01', 'interval' => 14,
                    'orphaned_at' => '2026-03-01' }
    }
    plan.save!

    reconcile_plan!(plan, now: Date.new(2026, 3, 21))
    plan.reload

    assert_not plan.on_hand.key?('Ancient'), 'Entry orphaned >180 days ago should be purged'
    assert plan.on_hand.key?('Recent'), 'Entry orphaned <180 days ago should be preserved'
  end

  test 'reconcile! backfills orphaned_at for legacy orphaned entries' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Legacy' => { 'confirmed_at' => '1970-01-01', 'interval' => 7 }
    }
    plan.save!

    today = Date.new(2026, 3, 21)
    reconcile_plan!(plan, now: today)
    plan.reload

    assert plan.on_hand.key?('Legacy'), 'Legacy entry should not be purged immediately'
    assert_equal today.iso8601, plan.on_hand['Legacy']['orphaned_at'],
                 'orphaned_at should be backfilled to today for legacy entries'
  end

  test 'reconcile! is idempotent when nothing to prune' do
    plan = MealPlan.for_kitchen(@kitchen)
    version_before = plan.lock_version

    reconcile_plan!(plan)

    assert_equal version_before, plan.reload.lock_version
  end

  test 'removing custom item and reconciling expires and converts on_hand entry' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
    plan.state['on_hand'] = {
      'Birthday Candles' => { 'confirmed_at' => Date.current.iso8601, 'interval' => nil }
    }
    plan.save!

    plan.apply_action('custom_items', item: 'Birthday Candles', action: 'remove')
    reconcile_plan!(plan)
    plan.reload

    assert_empty plan.state['custom_items']
    entry = plan.on_hand['Birthday Candles']

    assert_equal '1970-01-01', entry['confirmed_at'], 'Orphaned entry should be expired'
    assert_equal 7, entry['interval'], 'Null interval should be converted since custom item removed'
    assert_empty plan.effective_on_hand, 'Expired entry should not appear in effective_on_hand'
  end

  test 'reconcile! removes deleted recipe slugs from selections' do
    category = Category.find_or_create_by!(name: 'Test', slug: 'test', kitchen: @kitchen)
    MarkdownImporter.import("# Exists\n\n## Step (do it)\n\n- Flour, 1 cup\n\nDo it.\n", kitchen: @kitchen, category:)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'exists', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'gone', selected: true)

    reconcile_plan!(plan)

    assert_includes plan.state['selected_recipes'], 'exists'
    assert_not_includes plan.state['selected_recipes'], 'gone'
  end

  test 'reconcile! removes deleted quick bite IDs from selections' do
    @kitchen.update!(quick_bites_content: "## Snacks\n- Nachos: Chips\n")

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    plan.apply_action('select', type: 'quick_bite', slug: 'gone-bite', selected: true)

    reconcile_plan!(plan)

    assert_includes plan.state['selected_quick_bites'], 'nachos'
    assert_not_includes plan.state['selected_quick_bites'], 'gone-bite'
  end

  # --- Case-insensitive custom items (issue #156) ---

  test 'adding custom item ignores case-insensitive duplicate' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Butter', action: 'add')
    list.apply_action('custom_items', item: 'butter', action: 'add')

    assert_equal ['Butter'], list.state['custom_items']
  end

  test 'removing custom item is case-insensitive' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Butter', action: 'add')
    list.apply_action('custom_items', item: 'butter', action: 'remove')

    assert_empty list.state['custom_items']
  end

  # -- Cook History --

  test 'recipe deselect appends cook history entry' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

    history = plan.cook_history

    assert_equal 1, history.size
    assert_equal 'focaccia', history.first['slug']
    assert_predicate history.first['at'], :present?
  end

  test 'quick bite deselect does not append cook history' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: false)

    assert_empty plan.cook_history
  end

  test 'cook history accumulates multiple entries for same recipe' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

    assert_equal 2, plan.cook_history.size
  end

  test 'cook history prunes entries older than 90 days' do
    plan = MealPlan.for_kitchen(@kitchen)
    # Seed state with two entries: one stale, one fresh
    plan.state['cook_history'] = [
      { 'slug' => 'old-recipe', 'at' => 91.days.ago.iso8601 },
      { 'slug' => 'fresh-recipe', 'at' => 10.days.ago.iso8601 }
    ]
    plan.save!

    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

    slugs = plan.cook_history.pluck('slug')

    assert_not_includes slugs, 'old-recipe'
    assert_includes slugs, 'fresh-recipe'
    assert_includes slugs, 'focaccia'
  end

  test 'cook history is preserved across other state changes' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)
    plan.apply_action('check', item: 'milk', checked: true)

    assert_equal 1, plan.cook_history.size
    assert_equal 'focaccia', plan.cook_history.first['slug']
  end

  # --- on_hand check/uncheck ---

  test 'checking off a new item creates on_hand entry with interval 7 and ease 2.0' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Flour', checked: true)

    entry = plan.on_hand['Flour']

    assert_equal Date.current.iso8601, entry['confirmed_at']
    assert_equal 7, entry['interval']
    assert_in_delta 2.0, entry['ease']
  end

  test 'checking off a custom item creates on_hand entry with null interval and null ease' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Birthday candles', checked: true, custom: true)

    entry = plan.on_hand['Birthday candles']

    assert_equal Date.current.iso8601, entry['confirmed_at']
    assert_nil entry['interval']
    assert_nil entry['ease']
  end

  test 'checking off an existing item on a different day grows by ease factor' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
    }
    plan.save!

    plan.apply_action('check', item: 'Flour', checked: true, now: Date.new(2026, 3, 10))

    entry = plan.on_hand['Flour']

    assert_equal '2026-03-10', entry['confirmed_at']
    assert_in_delta 14.0, entry['interval']
    assert_in_delta 2.1, entry['ease']
  end

  test 'nil existing interval treated as starting interval with default ease' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Paper Towels' => { 'confirmed_at' => '2026-03-01', 'interval' => nil }
    }
    plan.save!

    plan.apply_action('check', item: 'Paper Towels', checked: true, custom: false, now: Date.new(2026, 3, 10))

    assert_in_delta 14.0, plan.on_hand['Paper Towels']['interval'], 0.1,
                    'nil interval treated as 7, grown by default ease 2.0 to 14'
    assert_in_delta 2.1, plan.on_hand['Paper Towels']['ease']
  end

  test 'interval caps at 180 days' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Salt' => { 'confirmed_at' => '2026-01-01', 'interval' => 100, 'ease' => 2.5 }
    }
    plan.save!

    plan.apply_action('check', item: 'Salt', checked: true, now: Date.new(2026, 3, 10))

    assert_in_delta 180.0, plan.on_hand['Salt']['interval'], 0.1,
                    'interval should cap at MAX_INTERVAL (180)'
    assert_in_delta 2.5, plan.on_hand['Salt']['ease'], 0.001,
                    'ease already at max should stay at max'
  end

  test 'checking off same item on same day is idempotent' do
    plan = MealPlan.for_kitchen(@kitchen)
    today = Date.new(2026, 3, 15)
    plan.apply_action('check', item: 'Flour', checked: true, now: today)
    version_after_first = plan.lock_version

    plan.apply_action('check', item: 'Flour', checked: true, now: today)

    assert_equal 7, plan.on_hand['Flour']['interval'], 'interval should not grow on same-day re-check'
    assert_in_delta 2.0, plan.on_hand['Flour']['ease'], 0.001, 'ease should not change on same-day re-check'
    assert_equal version_after_first, plan.lock_version, 'no save on idempotent check'
  end

  test 'expired item re-confirmed grows by ease factor' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
    }
    plan.save!

    plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 3, 20))

    assert_in_delta 14.0, plan.on_hand['Milk']['interval']
    assert_in_delta 2.1, plan.on_hand['Milk']['ease']
    assert_equal '2026-03-20', plan.on_hand['Milk']['confirmed_at']
  end

  test 'unchecking a custom item deletes it from on_hand' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Candles', checked: true, custom: true)
    plan.apply_action('check', item: 'Candles', checked: false, custom: true)

    assert_not plan.on_hand.key?('Candles')
  end

  test 'unchecking a non-custom item marks it depleted instead of deleting' do
    plan = MealPlan.for_kitchen(@kitchen)
    today = Date.new(2026, 3, 15)
    plan.state['on_hand'] = {
      'Milk' => { 'confirmed_at' => '2026-03-10', 'interval' => 14, 'ease' => 2.1 }
    }
    plan.save!

    plan.apply_action('check', item: 'Milk', checked: false, now: today)

    entry = plan.on_hand['Milk']

    assert entry, 'Non-custom entry should not be deleted'
    assert_equal MealPlan::ORPHAN_SENTINEL, entry['confirmed_at']
    assert_equal today.iso8601, entry['depleted_at']
    assert_equal 7, entry['interval'], 'Observed 5 days floors to STARTING_INTERVAL (7)'
    assert_in_delta 1.47, entry['ease'], 0.01, 'Ease penalized: 2.1 * 0.7'
  end

  test 'depleted observed period uses actual days when greater than STARTING_INTERVAL' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Butter' => { 'confirmed_at' => '2026-03-01', 'interval' => 28, 'ease' => 2.0 }
    }
    plan.save!

    plan.apply_action('check', item: 'Butter', checked: false, now: Date.new(2026, 3, 15))

    assert_equal 14, plan.on_hand['Butter']['interval'], 'Observed 14 days > 7, use observed'
  end

  test 'depleted ease penalty floors at MIN_EASE' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Eggs' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 1.2 }
    }
    plan.save!

    plan.apply_action('check', item: 'Eggs', checked: false, now: Date.new(2026, 3, 10))

    assert_in_delta 1.1, plan.on_hand['Eggs']['ease'], 0.001,
                    'Ease 1.2 * 0.7 = 0.84, floors to MIN_EASE (1.1)'
  end

  test 'unchecking an item succeeds even when on_hand key has different casing' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'flour' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7, 'ease' => 2.0 }
    }
    plan.save!

    plan.apply_action('check', item: 'Flour', checked: false, now: Date.current)

    entry = plan.on_hand['flour']

    assert entry, 'Should mark depleted under original key'
    assert_equal MealPlan::ORPHAN_SENTINEL, entry['confirmed_at']
  end

  test 'checking re-keys on_hand entry to new canonical form' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7, 'ease' => 2.0 }
    }
    plan.save!

    plan.apply_action('check', item: 'Flour', checked: true, now: Date.new(2026, 3, 10))

    assert plan.on_hand.key?('Flour'), 'Entry should be re-keyed to new canonical form'
    assert_not plan.on_hand.key?('flour'), 'Old key should be removed'
    assert_in_delta 14.0, plan.on_hand['Flour']['interval']
    assert_in_delta 2.1, plan.on_hand['Flour']['ease']
  end

  test 'depleted re-check preserves interval and ease without growth' do
    plan = MealPlan.for_kitchen(@kitchen)
    today = Date.new(2026, 3, 15)
    plan.state['on_hand'] = {
      'Milk' => { 'confirmed_at' => MealPlan::ORPHAN_SENTINEL, 'interval' => 10,
                  'ease' => 1.47, 'depleted_at' => '2026-03-14' }
    }
    plan.save!

    plan.apply_action('check', item: 'Milk', checked: true, now: today)

    entry = plan.on_hand['Milk']

    assert_equal today.iso8601, entry['confirmed_at']
    assert_equal 10, entry['interval'], 'Interval should be preserved, not grown'
    assert_in_delta 1.47, entry['ease'], 0.001, 'Ease should be preserved, not grown'
    assert_nil entry['depleted_at'], 'depleted_at should be cleared'
  end

  test 'uncheck + re-check same day preserves learned interval' do
    plan = MealPlan.for_kitchen(@kitchen)
    today = Date.new(2026, 3, 15)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 28, 'ease' => 2.1 }
    }
    plan.save!

    plan.apply_action('check', item: 'Flour', checked: false, now: today)

    depleted_entry = plan.on_hand['Flour']

    assert_equal 14, depleted_entry['interval'], 'Observed 14 days'

    plan.apply_action('check', item: 'Flour', checked: true, now: today)

    entry = plan.on_hand['Flour']

    assert_equal today.iso8601, entry['confirmed_at']
    assert_equal 14, entry['interval'], 'Re-check of depleted preserves interval'
    assert_nil entry['depleted_at']
  end

  test 'ease caps at MAX_EASE' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Salt' => { 'confirmed_at' => '2026-03-01', 'interval' => 50, 'ease' => 2.5 }
    }
    plan.save!

    plan.apply_action('check', item: 'Salt', checked: true, now: Date.new(2026, 3, 10))

    assert_in_delta 2.5, plan.on_hand['Salt']['ease'], 0.001,
                    'Ease should cap at MAX_EASE (2.5)'
    assert_in_delta 125.0, plan.on_hand['Salt']['interval'], 0.1,
                    'interval = 50 * 2.5 = 125'
  end

  test 'full convergence scenario: milk settling around 10 days' do
    plan = MealPlan.for_kitchen(@kitchen)
    day = Date.new(2026, 1, 1)

    # Day 0: first check — interval 7, ease 2.0
    plan.apply_action('check', item: 'Milk', checked: true, now: day)

    assert_equal 7, plan.on_hand['Milk']['interval']
    assert_in_delta 2.0, plan.on_hand['Milk']['ease']

    # Day 8: still have it, re-confirm — interval 14, ease 2.1
    plan.apply_action('check', item: 'Milk', checked: true, now: day + 8)

    assert_in_delta 14.0, plan.on_hand['Milk']['interval']
    assert_in_delta 2.1, plan.on_hand['Milk']['ease']

    # Day 18: ran out after 10 days (before 14-day interval expired)
    # Uncheck — observed 10 days, ease penalized
    plan.apply_action('check', item: 'Milk', checked: false, now: day + 18)

    assert_equal 10, plan.on_hand['Milk']['interval'], 'Observed 10 days'
    assert_in_delta 1.47, plan.on_hand['Milk']['ease'], 0.01, '2.1 * 0.7'

    # Day 18: re-check (just bought more) — no growth, preserves depleted state
    plan.apply_action('check', item: 'Milk', checked: true, now: day + 18)

    assert_equal 10, plan.on_hand['Milk']['interval']
    assert_in_delta 1.47, plan.on_hand['Milk']['ease'], 0.01

    # Day 29: still have it after ~11 days, re-confirm — grows
    plan.apply_action('check', item: 'Milk', checked: true, now: day + 29)

    assert_in_delta 14.7, plan.on_hand['Milk']['interval'], 0.1, '10 * 1.47'
    assert_in_delta 1.57, plan.on_hand['Milk']['ease'], 0.01, '1.47 + 0.1'
  end

  # -- effective_on_hand --

  test 'effective_on_hand returns non-expired entries' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 14 },
      'Salt' => { 'confirmed_at' => '2026-03-01', 'interval' => 56 }
    }
    plan.save!

    result = plan.effective_on_hand(now: Date.new(2026, 3, 20))

    assert result.key?('Salt'), 'Salt (56-day interval, confirmed 19 days ago) should still be on hand'
    assert_not result.key?('Flour'), 'Flour (14-day interval, confirmed 19 days ago) should be expired'
  end

  test 'effective_on_hand excludes expired entries' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
    }
    plan.save!

    result = plan.effective_on_hand(now: Date.new(2026, 3, 9))

    assert_not result.key?('Milk'), 'Milk confirmed 8 days ago with 7-day interval should be expired'
  end

  test 'effective_on_hand preserves custom items with null interval' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Birthday candles' => { 'confirmed_at' => '2026-01-01', 'interval' => nil }
    }
    plan.save!

    result = plan.effective_on_hand(now: Date.new(2026, 12, 31))

    assert result.key?('Birthday candles'), 'Custom items (null interval) never expire'
  end

  test 'effective_on_hand boundary: item expires on exact day' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
    }
    plan.save!

    day_before = plan.effective_on_hand(now: Date.new(2026, 3, 7))
    exact_day = plan.effective_on_hand(now: Date.new(2026, 3, 8))
    day_after = plan.effective_on_hand(now: Date.new(2026, 3, 9))

    assert day_before.key?('Flour'), 'Day 7 (confirmed_at + 6): still on hand'
    assert exact_day.key?('Flour'), 'Day 8 (confirmed_at + 7): boundary, still on hand'
    assert_not day_after.key?('Flour'), 'Day 9 (confirmed_at + 8): expired'
  end
end
