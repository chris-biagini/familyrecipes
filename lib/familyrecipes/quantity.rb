# frozen_string_literal: true

# Quantity value object
#
# Immutable representation of an ingredient quantity (value + unit).
# Replaces bare [value, unit] tuples throughout the codebase.

Quantity = Data.define(:value, :unit) do
  def to_json(*args)
    [value, unit].to_json(*args)
  end
end
