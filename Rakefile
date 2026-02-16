require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Remove generated output"
task :clean do
  rm_rf "output"
  puts "Cleaned output/"
end

task default: :test

desc "Build the site"
task :build do
  ruby "bin/generate"
end

desc "Start the dev server (PORT=N to override, default 8888)"
task :serve do
  ruby "bin/serve #{ENV['PORT']}"
end
