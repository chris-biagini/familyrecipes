# frozen_string_literal: true

# Defines the top-level :test (Minitest) and :lint (RuboCop) tasks. The default
# rake task runs both. RuboCop is optional — if the gem isn't available (e.g.,
# in a production image), the default falls back to :test only.
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:lint)
  task default: %i[lint test brand:check_residue]
rescue LoadError
  task default: :test
end
