# frozen_string_literal: true

# Orchestrates all direct MealPlan mutations: action application (select,
# check, custom items, have_it, need_it, quick_add). Validates input (e.g.
# custom item length) before mutating. Canonicalization boundary for
# check/have_it/need_it: resolves item names via IngredientResolver; check
# also detects custom items (case-insensitive). quick_add is the search
# overlay's "add to grocery list" action — resolves name, adds to custom
# items if unrecognized, and marks the item as needed. Returns QuickAddResult
# with :added, :already_on_list, or :failed status.
#
# - MealPlan: singleton-per-kitchen JSON state record
# - IngredientCatalog.resolver_for: builds resolver for canonical name lookup
# - Kitchen.finalize_writes: centralized post-write finalization
class MealPlanWriteService
  Result = Data.define(:success, :errors)

  QuickAddResult = Data.define(:status, :errors) do
    def success? = errors.empty?
  end

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

    mutate_plan do |plan|
      enriched = enrich_check_params(plan, action_type, **params)
      plan.apply_action(action_type, **enriched)
    end
    Kitchen.finalize_writes(kitchen)
    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def mutate_plan
    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { yield plan }
    plan
  end

  def enrich_check_params(plan, action_type, **params)
    return params unless %w[check have_it need_it].include?(action_type)

    resolver = IngredientCatalog.resolver_for(kitchen)
    canonical = resolver.resolve(params[:item].to_s)

    return params.merge(item: canonical) unless action_type == 'check'

    custom = plan.custom_items.any? { |k, _| k.casecmp?(params[:item].to_s) }
    params.merge(item: canonical, custom:)
  end

  def validate_action(action_type, **params)
    return [] unless %w[custom_items quick_add].include?(action_type)

    item = params[:item].to_s
    return ['Item name is required'] if item.blank?

    max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
    return ["Custom item name is too long (max #{max} characters)"] if item.size > max

    []
  end

  def apply_quick_add(item:, aisle: 'Miscellaneous', **)
    resolver = IngredientCatalog.resolver_for(kitchen)
    canonical = resolver.resolve(item)
    plan = MealPlan.for_kitchen(kitchen)

    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan, resolver:).visible_names
    raw_entry = plan.on_hand.find { |k, _| k.casecmp?(canonical) }&.last

    status = quick_add_status(canonical, visible, plan.effective_on_hand, raw_entry)
    execute_quick_add(status, canonical, aisle)

    QuickAddResult.new(status:, errors: [])
  end

  def quick_add_status(canonical, visible, effective_on_hand, raw_entry)
    return :moved_to_buy if effective_on_hand.key?(canonical)
    return :already_needed if visible.include?(canonical) && (raw_entry.nil? || raw_entry.key?('depleted_at'))
    return :moved_to_buy if visible.include?(canonical) && raw_entry
    return :added unless visible.include?(canonical)

    :added
  end

  def execute_quick_add(status, canonical, aisle)
    case status
    when :moved_to_buy
      MealPlanWriteService.apply_action(kitchen:, action_type: 'need_it', item: canonical)
    when :added
      MealPlanWriteService.apply_action(kitchen:, action_type: 'custom_items', item: canonical, action: 'add', aisle:)
    end
  end
end
