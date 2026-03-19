# frozen_string_literal: true

# Template method base class for list management services (aisles, categories,
# tags). Provides the shared skeleton: validate -> transaction(renames, deletes,
# ordering) -> finalize. Subclasses override hooks for their specific cascade
# behavior. Input normalization (coercing renames/deletes to clean Ruby types)
# happens once here so subclasses never need defensive type guards.
#
# - Kitchen.finalize_writes: centralized post-write finalization
# - AisleWriteService, CategoryWriteService, TagWriteService: subclasses
class ListWriteService
  Result = Data.define(:success, :errors)

  def self.update(kitchen:, renames: {}, deletes: [], **params)
    new(kitchen:).update(renames:, deletes:, **params)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(renames: {}, deletes: [], **params)
    renames = normalize_renames(renames)
    deletes = Array(deletes)

    errors = validate_changeset(renames:, deletes:, **params)
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      apply_renames(renames)
      apply_deletes(deletes)
      apply_ordering(**params)
    end

    Kitchen.finalize_writes(kitchen)
    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def validate_changeset(renames:, deletes:, **) = [] # rubocop:disable Lint/UnusedMethodArgument
  def apply_renames(_renames) = nil
  def apply_deletes(_deletes) = nil
  def apply_ordering(**) = nil

  def normalize_renames(renames)
    case renames
    when Hash then renames
    when ActionController::Parameters then renames.to_unsafe_h
    else {}
    end
  end

  def validate_order(items, max_items:, max_name_length:, exact_dupes: true)
    errors = []
    errors << "Too many items (maximum #{max_items})." if items.size > max_items

    long = items.select { |name| name.size > max_name_length }
    errors.concat(long.map { |name| "\"#{name}\" is too long (maximum #{max_name_length} characters)." })

    dupes = items.group_by(&:downcase)
                 .select { |_, v| exact_dupes ? v.size > 1 : v.uniq.size > 1 }
                 .values.map(&:first)
    errors.concat(dupes.map { |name| "\"#{name}\" appears more than once (case-insensitive)." })
    errors
  end

  def validate_renames_length(renames, max_length)
    renames.values
           .select { |name| name.size > max_length }
           .map { |name| "\"#{name}\" exceeds maximum length of #{max_length} characters." }
  end
end
