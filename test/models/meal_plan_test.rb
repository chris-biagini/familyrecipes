# frozen_string_literal: true

require 'test_helper'

class MealPlanTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    MealPlan.where(kitchen: @kitchen).delete_all
  end

  def reconcile_plan!(plan, now: Date.current)
    visible = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible, now:)
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

    assert_equal({}, list.on_hand)
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

  test 'reconcile! prunes orphaned on_hand entries not in visible names' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Phantom' => { 'confirmed_at' => Date.current.iso8601, 'interval' => 7 }
    }
    plan.save!

    reconcile_plan!(plan)
    plan.reload

    assert_empty plan.on_hand
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
    assert_not plan.on_hand.key?('Phantom')
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

    assert plan.on_hand.key?('birthday candles')
  end

  test 'reconcile! prunes expired entries' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    md = "# Bread\n\n## Mix (combine)\n\n- Flour, 2 cups\n\nMix.\n"
    MarkdownImporter.import(md, kitchen: @kitchen, category: @category)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-01-01', 'interval' => 7 }
    }
    plan.save!

    reconcile_plan!(plan, now: Date.new(2026, 3, 21))
    plan.reload

    assert_not plan.on_hand.key?('Flour'), 'Expired entry should be pruned'
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

  test 'reconcile! is idempotent when nothing to prune' do
    plan = MealPlan.for_kitchen(@kitchen)
    version_before = plan.lock_version

    reconcile_plan!(plan)

    assert_equal version_before, plan.reload.lock_version
  end

  test 'removing custom item and reconciling cleans up on_hand entry' do
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
    assert_empty plan.on_hand
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

  test 'checking off a new item creates on_hand entry with interval 7' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Flour', checked: true)

    entry = plan.on_hand['Flour']

    assert_equal Date.current.iso8601, entry['confirmed_at']
    assert_equal 7, entry['interval']
  end

  test 'checking off a custom item creates on_hand entry with null interval' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Birthday candles', checked: true, custom: true)

    entry = plan.on_hand['Birthday candles']

    assert_equal Date.current.iso8601, entry['confirmed_at']
    assert_nil entry['interval']
  end

  test 'checking off an existing item on a different day doubles the interval' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
    }
    plan.save!

    plan.apply_action('check', item: 'Flour', checked: true, now: Date.new(2026, 3, 10))

    entry = plan.on_hand['Flour']

    assert_equal '2026-03-10', entry['confirmed_at']
    assert_equal 14, entry['interval']
  end

  test 'interval caps at 56 days' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Salt' => { 'confirmed_at' => '2026-01-01', 'interval' => 56 }
    }
    plan.save!

    plan.apply_action('check', item: 'Salt', checked: true, now: Date.new(2026, 3, 10))

    assert_equal 56, plan.on_hand['Salt']['interval']
  end

  test 'checking off same item on same day is idempotent' do
    plan = MealPlan.for_kitchen(@kitchen)
    today = Date.new(2026, 3, 15)
    plan.apply_action('check', item: 'Flour', checked: true, now: today)
    version_after_first = plan.lock_version

    plan.apply_action('check', item: 'Flour', checked: true, now: today)

    assert_equal 7, plan.on_hand['Flour']['interval'], 'interval should not double on same-day re-check'
    assert_equal version_after_first, plan.lock_version, 'no save on idempotent check'
  end

  test 'expired item re-confirmed doubles interval from previous value' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 7 }
    }
    plan.save!

    plan.apply_action('check', item: 'Milk', checked: true, now: Date.new(2026, 3, 20))

    assert_equal 14, plan.on_hand['Milk']['interval']
    assert_equal '2026-03-20', plan.on_hand['Milk']['confirmed_at']
  end

  test 'unchecking an item deletes it from on_hand' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Milk', checked: true)
    plan.apply_action('check', item: 'Milk', checked: false)

    assert_not plan.on_hand.key?('Milk')
  end

  test 'unchecking then re-checking starts fresh at interval 7' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.state['on_hand'] = {
      'Flour' => { 'confirmed_at' => '2026-03-01', 'interval' => 28 }
    }
    plan.save!

    plan.apply_action('check', item: 'Flour', checked: false)
    plan.apply_action('check', item: 'Flour', checked: true)

    assert_equal 7, plan.on_hand['Flour']['interval']
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
