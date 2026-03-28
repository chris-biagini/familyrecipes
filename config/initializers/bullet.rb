# frozen_string_literal: true

# Bullet: automatic N+1 query detection in development and test.
# In dev, warnings appear in the page footer and Rails log. In test, Bullet
# raises so new N+1 regressions fail the test suite.
if defined?(Bullet)
  Bullet.enable = true
  Bullet.bullet_logger = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
  Bullet.raise = Rails.env.test?
end
