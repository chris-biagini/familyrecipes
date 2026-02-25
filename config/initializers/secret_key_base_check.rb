# frozen_string_literal: true

# Fail fast if SECRET_KEY_BASE is missing in production.
# Without it, signed cookies (session IDs) use a nil-derived key.
if Rails.env.production? && ENV['SECRET_KEY_BASE'].blank?
  raise 'SECRET_KEY_BASE must be set in production'
end
