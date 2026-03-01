# frozen_string_literal: true

# Immutable value object for a parsed quantity (e.g., 2.0 cups). Used throughout
# the parser and nutrition pipeline as the standard unit of measurement. Must
# define both #to_json and #as_json — ActiveSupport calls #as_json on nested
# objects, not #to_json, so without both, quantities serialize as hashes when
# embedded in arrays/hashes.
Quantity = Data.define(:value, :unit) do
  def as_json(*)
    [value, unit]
  end

  def to_json(*args)
    as_json.to_json(*args)
  end
end
