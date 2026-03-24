# frozen_string_literal: true

# Orchestrates all meal plan mutations: select, check, custom items, have_it,
# need_it, quick_add. Delegates to normalized AR models (MealPlanSelection,
# OnHandEntry, CustomGroceryItem, CookHistoryEntry) instead of mutating JSON.
# Canonicalizes ingredient names via IngredientResolver before persisting.
#
# - MealPlanSelection: recipe/quick bite toggle
# - OnHandEntry: per-ingredient SM-2 adaptive tracking
# - CustomGroceryItem: user-added non-recipe grocery items
# - CookHistoryEntry: append-only cook event log
# - Kitchen.finalize_writes: centralized post-write finalization
class MealPlanWriteService
  Result = Data.define(:success, :errors)

  QuickAddResult = Data.define(:status, :errors) do
    def success? = errors.empty?
  end

  SELECTABLE_TYPES = { 'recipe' => 'Recipe', 'quick_bite' => 'QuickBite' }.freeze

  def self.apply_action(kitchen:, action_type:, **params)
    new(kitchen:).apply_action(action_type:, **params)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def apply_action(action_type:, **params)
    errors = validate_action(action_type, **params)
    return Result.new(success: false, errors:) if errors.any?
    return apply_quick_add(**params) if action_type == 'quick_add'

    send(:"apply_#{action_type}", **params)
    Kitchen.finalize_writes(kitchen)
    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def apply_select(type:, slug:, selected:, **)
    selectable_type = SELECTABLE_TYPES.fetch(type, type)
    MealPlanSelection.toggle(kitchen:, type: selectable_type, id: slug, selected:)
    record_cook_history(slug) if !selected && selectable_type == 'Recipe'
  end

  def apply_check(item:, checked:, **)
    resolver = build_resolver
    canonical = resolver.resolve(item.to_s)
    custom_item = find_custom_item(item.to_s)
    canonical = custom_item.name if custom_item
    entry = find_or_init_on_hand(canonical)

    checked ? entry.check!(custom_item:) : entry.uncheck!(custom_item:)
  end

  def apply_custom_items(item:, action:, aisle: 'Miscellaneous', **)
    if action == 'add'
      CustomGroceryItem.create!(kitchen:, name: item, aisle:, last_used_at: Date.current)
    else
      CustomGroceryItem.find_by!(kitchen:, name: item).destroy
    end
  end

  def apply_have_it(item:, **)
    entry = resolve_and_find(item.to_s)
    entry.have_it!
  end

  def apply_need_it(item:, **)
    entry = resolve_and_find(item.to_s)
    entry.need_it!
  end

  def apply_quick_add(item:, aisle: 'Miscellaneous', **)
    resolver = build_resolver
    canonical = resolver.resolve(item)
    status = determine_quick_add_status(canonical, resolver)
    execute_quick_add_directly(status, canonical, aisle)

    QuickAddResult.new(status:, errors: [])
  end

  def determine_quick_add_status(canonical, resolver)
    entry = OnHandEntry.find_by(kitchen:, ingredient_name: canonical)
    return :moved_to_buy if entry&.depleted_at.nil? && entry&.persisted?

    visible = ShoppingListBuilder.visible_names_for(kitchen:, resolver:)
    return :already_needed if visible.include?(canonical) && entry&.depleted_at.present?
    return :moved_to_buy if visible.include?(canonical)

    :added
  end

  def execute_quick_add_directly(status, canonical, aisle)
    case status
    when :moved_to_buy
      deplete_on_hand(canonical)
      Kitchen.finalize_writes(kitchen)
    when :added
      CustomGroceryItem.create!(kitchen:, name: canonical, aisle:, last_used_at: Date.current)
      Kitchen.finalize_writes(kitchen)
    end
  end

  # Marks an on-hand entry as depleted. For existing entries, delegates to
  # need_it! which handles interval blending. For new entries (visible via
  # recipe but never tracked), creates a sentinel-based depleted record.
  def deplete_on_hand(canonical)
    entry = find_or_init_on_hand(canonical)

    if entry.new_record?
      entry.assign_attributes(
        confirmed_at: Date.parse(OnHandEntry::ORPHAN_SENTINEL),
        depleted_at: Date.current,
        interval: OnHandEntry::STARTING_INTERVAL,
        ease: OnHandEntry::STARTING_EASE
      )
      entry.save!
    else
      entry.need_it!
    end
  end

  def validate_action(action_type, **params)
    return [] unless %w[custom_items quick_add].include?(action_type)

    item = params[:item].to_s
    return ['Item name is required'] if item.blank?

    max = CustomGroceryItem::MAX_NAME_LENGTH
    return ["Custom item name is too long (max #{max} characters)"] if item.size > max

    []
  end

  def build_resolver
    IngredientCatalog.resolver_for(kitchen)
  end

  def resolve_and_find(item)
    canonical = build_resolver.resolve(item)
    find_or_init_on_hand(canonical)
  end

  def find_or_init_on_hand(canonical)
    OnHandEntry.find_or_initialize_by(kitchen:, ingredient_name: canonical)
  end

  def find_custom_item(name)
    CustomGroceryItem.find_by(name:)
  end

  def record_cook_history(slug)
    CookHistoryEntry.record(kitchen:, recipe_slug: slug)
  end
end
