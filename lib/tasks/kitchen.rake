# frozen_string_literal: true

namespace :kitchen do # rubocop:disable Metrics/BlockLength
  desc 'Print the join code for a kitchen (KITCHEN=slug)'
  task show_join_code: :environment do
    slug = ENV.fetch('KITCHEN', nil)
    abort 'Usage: rake kitchen:show_join_code KITCHEN=slug-here' unless slug

    kitchen = ActsAsTenant.without_tenant { Kitchen.find_by(slug:) }
    abort "No kitchen found with slug '#{slug}'" unless kitchen

    puts "Kitchen: #{kitchen.name}"
    puts "Join code: #{kitchen.join_code}"
  end

  desc 'Create a kitchen + owner user (args: name, email, owner_name)'
  task :create, %i[name email owner_name] => :environment do |_t, args|
    abort 'Usage: rake "kitchen:create[Kitchen Name,owner@example.com,Owner Name]"' if args.to_a.any?(&:blank?)

    ActsAsTenant.without_tenant do
      ActiveRecord::Base.transaction do
        kitchen = Kitchen.create!(
          name: args[:name],
          slug: args[:name].to_s.parameterize.presence || 'kitchen'
        )
        user = User.find_or_create_by!(email: args[:email]) { |u| u.name = args[:owner_name] }
        Membership.create!(kitchen:, user:, role: 'owner')
        MealPlan.create!(kitchen:)

        puts "Created kitchen: #{kitchen.name} (#{kitchen.slug})"
        puts "Owner: #{user.name} <#{user.email}>"
        puts "Join code: #{kitchen.join_code}"
      end
    end
  end
end
