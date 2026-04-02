# frozen_string_literal: true

# Runs the doc-vs-app contract verification tests. Checks that app sections
# and settings referenced in docs/help/ actually exist in the application.
#
# Depends on: test/release/doc_contract_check.rb

namespace :release do
  namespace :audit do
    desc 'Verify help docs match app behavior'
    task docs: :environment do
      puts '--- Doc contract verification ---'
      system('ruby -Itest test/release/doc_contract_check.rb')

      if $CHILD_STATUS.success?
        puts 'Doc contracts: verified ✓'
      else
        abort 'Doc contract verification failed — see above.'
      end
    end
  end
end
