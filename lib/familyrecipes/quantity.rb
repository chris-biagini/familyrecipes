# frozen_string_literal: true

Quantity = Data.define(:value, :unit) do
  def as_json(*)
    [value, unit]
  end

  def to_json(*args)
    as_json.to_json(*args)
  end
end
