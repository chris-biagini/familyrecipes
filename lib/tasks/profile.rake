# frozen_string_literal: true

require_relative '../profile_baseline'

namespace :profile do
  desc 'Run performance baseline: measure key pages and asset sizes'
  task baseline: :environment do
    slug = ENV.fetch('KITCHEN', 'our-kitchen')
    kitchen = Kitchen.find_by!(slug:)
    ActsAsTenant.current_tenant = kitchen
    user = kitchen.memberships.first&.user || User.first

    abort "No kitchen '#{slug}' or user found. Run db:seed first." unless kitchen && user

    baseline = ProfileBaseline.new(kitchen, user)

    puts 'Profiling pages...'
    page_results = baseline.page_profiles

    puts 'Measuring assets...'
    asset_results = baseline.asset_profiles

    report = baseline.format_report(page_results, asset_results)
    puts "\n#{report}"

    log_path = Rails.root.join('tmp/profile_baselines.log')
    File.open(log_path, 'a') { |f| f.puts "\n#{report}\n" }
    puts "\nAppended to #{log_path}"
  end
end
