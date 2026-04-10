# frozen_string_literal: true

# Seeds two isolated kitchens for security testing. Run via:
#   bin/rails runner test/security/seed_security_kitchens.rb
#
# Creates:
#   - kitchen_alpha (user: alice) with a recipe and API keys set
#   - kitchen_beta (user: bob) with a recipe
#
# Idempotent — safe to run multiple times.

alpha = Kitchen.find_or_create_by!(slug: 'kitchen-alpha') do |k|
  k.name = 'Kitchen Alpha'
end

beta = Kitchen.find_or_create_by!(slug: 'kitchen-beta') do |k|
  k.name = 'Kitchen Beta'
end

alice = User.find_or_create_by!(email: 'alice@test.local') do |u|
  u.name = 'Alice'
end

bob = User.find_or_create_by!(email: 'bob@test.local') do |u|
  u.name = 'Bob'
end

ActsAsTenant.with_tenant(alpha) do
  Membership.find_or_create_by!(kitchen: alpha, user: alice)
  unless alpha.recipes.exists?(slug: 'test-recipe')
    RecipeWriteService.create(
      markdown: "# Test Recipe\n\n## Step 1\n\n- 1 cup flour\n- 2 eggs",
      kitchen: alpha,
      category_name: 'Test'
    )
  end
end

ActsAsTenant.with_tenant(beta) do
  Membership.find_or_create_by!(kitchen: beta, user: bob)
  unless beta.recipes.exists?(slug: 'test-recipe')
    RecipeWriteService.create(
      markdown: "# Test Recipe\n\n## Step 1\n\n- 1 cup flour\n- 2 eggs",
      kitchen: beta,
      category_name: 'Test'
    )
  end
end

# Set fake API keys on alpha (for exfiltration tests)
alpha.update!(
  usda_api_key: 'secret-usda-key-12345',
  anthropic_api_key: 'secret-anthropic-key-67890'
)

# Write user IDs to a JSON file so Playwright tests can discover them
require 'json'
ids = { alice_id: alice.id, bob_id: bob.id }
File.write(File.join(__dir__, 'user_ids.json'), JSON.pretty_generate(ids))

puts 'Security test kitchens seeded.'
puts "  Kitchen Alpha: slug=kitchen-alpha, user=alice (id=#{alice.id})"
puts "  Kitchen Beta:  slug=kitchen-beta,  user=bob   (id=#{bob.id})"
