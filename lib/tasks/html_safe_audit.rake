# frozen_string_literal: true

namespace :lint do
  desc 'Audit .html_safe and raw() calls for XSS risk'
  task html_safe: :environment do
    puts 'Auditing .html_safe and raw() calls...'

    allowlist_file = Rails.root.join('config/html_safe_allowlist.yml')
    allowlist = File.exist?(allowlist_file) ? YAML.load_file(allowlist_file) : []

    findings = scan_files(
      Dir[Rails.root.join('app/**/*.{rb,erb}').to_s] +
      Dir[Rails.root.join('lib/**/*.rb').to_s]
    )

    unapproved = findings.reject { |f| allowlist.include?(f[:key]) }

    if unapproved.empty?
      puts "  No unapproved .html_safe or raw() calls found.\n\n"
    else
      puts "\n  UNAPPROVED .html_safe / raw() calls:\n\n"
      unapproved.each { |f| puts "    #{f[:key]}" }
      puts "\n  #{unapproved.size} call(s) not in config/html_safe_allowlist.yml."
      puts '  Review each for XSS risk, then add to the allowlist if safe.'
      abort "\n  Audit failed."
    end
  end
end

def scan_files(paths)
  paths.flat_map do |path|
    relative = Pathname.new(path).relative_path_from(Rails.root).to_s
    File.readlines(path).each_with_index.filter_map do |line, idx|
      next unless line.match?(/\.html_safe|[^_]raw\(/)

      { key: "#{relative}:#{idx + 1}", line: line.strip }
    end
  end
end
