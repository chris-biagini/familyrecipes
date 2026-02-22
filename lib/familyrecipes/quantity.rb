# frozen_string_literal: true

# Quantity value object
#
# Immutable representation of an ingredient quantity (value + unit).
# Replaces bare [value, unit] tuples throughout the codebase.

Quantity = Data.define(:value, :unit) do
  def as_json(*)
    [value, unit]
  end

  def to_json(*args)
    as_json.to_json(*args)
  end
end
