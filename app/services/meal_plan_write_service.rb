# frozen_string_literal: true

# Orchestrates all direct MealPlan mutations: action application (select,
# check, custom items, have_it, need_it). Validates input (e.g. custom item
# length) before mutating. Canonicalization boundary for check/have_it/need_it:
# resolves item names via IngredientResolver; check also detects custom items
# (case-insensitive). Owns optimistic-locking retry for state changes.
# Post-write finalization (reconciliation, broadcast) is handled by
# Kitchen.finalize_writes.
#
# - MealPlan: singleton-per-kitchen JSON state record
# - IngredientCatalog.resolver_for: builds resolver for canonical name lookup
# - Kitchen.finalize_writes: centralized post-write finalization
class MealPlanWriteService
  Result = Data.define(:success, :errors)

  def self.apply_action(kitchen:, action_type:, **params)
    new(kitchen:).apply_action(action_type:, **params)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def apply_action(action_type:, **params)
    errors = validate_action(action_type, **params)
    return Result.new(success: false, errors:) if errors.any?

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

    custom = plan.custom_items.any? { |c| c.casecmp?(params[:item].to_s) }
    params.merge(item: canonical, custom:)
  end

  def validate_action(action_type, **params)
    return [] unless action_type == 'custom_items'

    max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
    return ["Custom item name is too long (max #{max} characters)"] if params[:item].to_s.size > max

    []
  end
end
