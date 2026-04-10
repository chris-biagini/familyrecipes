# frozen_string_literal: true

namespace :kitchen do
  desc 'Print the join code for a kitchen (KITCHEN=slug)'
  task show_join_code: :environment do
    slug = ENV.fetch('KITCHEN', nil)
    abort 'Usage: rake kitchen:show_join_code KITCHEN=slug-here' unless slug

    kitchen = ActsAsTenant.without_tenant { Kitchen.find_by(slug:) }
    abort "No kitchen found with slug '#{slug}'" unless kitchen

    puts "Kitchen: #{kitchen.name}"
    puts "Join code: #{kitchen.join_code}"
  end
end
