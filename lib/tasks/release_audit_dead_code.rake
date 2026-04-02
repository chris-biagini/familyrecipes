# frozen_string_literal: true

# Runs debride to find potentially unreachable methods in app/ and lib/,
# then filters results against config/debride_allowlist.txt. Fails if
# any un-allowlisted dead methods are found.

namespace :release do
  namespace :audit do
    desc 'Detect unreachable methods (dead code)'
    task dead_code: :environment do
      allowlist_path = Rails.root.join('config/debride_allowlist.txt')
      allowlist = load_debride_allowlist(allowlist_path)

      output = `bundle exec debride app/ lib/ 2>/dev/null`
      methods = parse_debride_output(output)
      unapproved = methods.reject { |m| allowlist.include?(m[:name]) }

      if unapproved.empty?
        puts "Dead code: 0 unreachable methods \u2713"
      else
        puts "\nPotentially unreachable methods:\n\n"
        unapproved.each { |m| puts "  #{m[:location]}  #{m[:name]}" }
        puts "\n#{unapproved.size} method(s) not in config/debride_allowlist.txt."
        puts 'Review each — if legitimate, add to the allowlist with a comment.'
        abort "\nDead code check failed."
      end
    end
  end
end

def load_debride_allowlist(path)
  return Set.new unless path.exist?

  path.readlines.filter_map do |line|
    stripped = line.strip
    stripped unless stripped.empty? || stripped.start_with?('#')
  end.to_set
end

def parse_debride_output(output)
  output.lines.filter_map do |line|
    match = line.match(/^\s+(\S+)\s+(.+:\d+)/)
    next unless match

    { name: match[1], location: match[2] }
  end
end
