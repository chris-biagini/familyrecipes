# frozen_string_literal: true

# Brand-residue check for the 2026-04-11 Mirepoix rebrand. Fails if any variant
# of the old "Family Recipes" brand is found in tracked files outside the
# frozen historical directories. Runs in CI (and manually) to prevent
# accidental reintroduction of old brand strings.
#
# Deliberately does NOT depend on :environment — the check is a pure string
# scan via `rg` and must keep working even if Rails boot is temporarily
# broken mid-rebrand. Rails/RakeEnvironment is disabled for that reason.
namespace :brand do # rubocop:disable Metrics/BlockLength
  desc 'Fail if any "Family Recipes" brand residue remains in tracked files'
  task :check_residue do # rubocop:disable Rails/RakeEnvironment
    require 'open3'

    pattern = '\bfamily[-_ ]?recipes?\b'
    excludes = %w[
      docs/superpowers/specs/**
      docs/superpowers/plans/**
      .git/**
    ]
    exclude_args = excludes.flat_map { |glob| ['--glob', "!#{glob}"] }
    # Trailing '.' is load-bearing: rg under Open3.capture2e reads from the
    # empty stdin pipe and silently reports clean unless given an explicit path.
    cmd = ['rg', '-i', '-c', '--no-heading', pattern, *exclude_args, '.']

    output, status = Open3.capture2e(*cmd)

    case status.exitstatus
    when 0
      total = output.lines.sum { |line| line.split(':').last.to_i }
      puts "Brand residue found (#{total} matches across #{output.lines.size} files):"
      puts output
      abort
    when 1
      puts "Clean: no 'Family Recipes' brand residue detected."
    else
      puts "rg error (exit #{status.exitstatus}):"
      puts output
      abort
    end
  end
end
