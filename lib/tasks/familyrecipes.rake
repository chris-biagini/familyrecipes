# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

RuboCop::RakeTask.new(:lint)

desc 'Remove generated output'
task :clean do
  rm_rf 'output'
  puts 'Cleaned output/'
end

desc 'Build the static site'
task :build do
  ruby 'bin/generate'
end

task default: %i[lint test]
