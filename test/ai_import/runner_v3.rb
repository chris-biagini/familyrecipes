#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Import prompt evaluation runner (v3). Standalone script — no Rails boot.
# Uses `claude -p` instead of direct API calls — runs on Max plan tokens.
#
# Key difference from runner.rb: `--system-prompt` replaces the Claude Code
# default system prompt, and `--tools ""` disables all tools. This makes
# the invocation behave like a bare API call.
#
# Usage:
#   ruby test/ai_import/runner_v3.rb [label]
#   ruby test/ai_import/runner_v3.rb --corpus=corpus_v3 [label]
#   ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_faithful.md [label]
#   ruby test/ai_import/runner_v3.rb --concurrency=5 [label]
#
# Collaborators:
# - claude CLI (`claude -p`) for import (Sonnet) and judging (default model)
# - Scorers::ParseChecker, FormatChecker, SystemCompatChecker for algorithmic checks
# - fidelity_judge_prompt.md, step_structure_judge_prompt.md for LLM judge rubrics

require 'json'
require 'fileutils'
require 'open3'

# ActiveSupport polyfill — parser uses .presence
class Object
  def presence
    self if respond_to?(:empty?) ? !empty? : !nil?
  end
end

require_relative '../../lib/familyrecipes'
require_relative 'scorers/parse_checker'
require_relative 'scorers/format_checker'
require_relative 'scorers/system_compat_checker'

BASE_DIR = File.expand_path(__dir__)
RESULTS_DIR = File.join(BASE_DIR, 'results')
LIB_DIR = File.expand_path('../../lib/familyrecipes', BASE_DIR)

CATEGORIES = %w[Baking Bread Breakfast Dessert Drinks Holiday Mains Pizza Sides Snacks Miscellaneous].freeze
TAGS = %w[vegetarian vegan gluten-free weeknight easy quick one-pot make-ahead
          freezer-friendly grilled roasted baked comfort-food holiday american
          italian mexican french japanese chinese indian thai].freeze

# --- CLI ---

def parse_args
  opts = { corpus: 'corpus_v3', prompt: 'ai_import_prompt_faithful.md', concurrency: 5, label: nil }

  ARGV.each do |arg|
    case arg
    when /\A--corpus=(.+)/ then opts[:corpus] = $1
    when /\A--prompt=(.+)/ then opts[:prompt] = $1
    when /\A--concurrency=(\d+)/ then opts[:concurrency] = $1.to_i
    else opts[:label] = arg
    end
  end

  opts[:corpus_dir] = File.join(BASE_DIR, opts[:corpus])
  opts[:prompt_path] = File.join(LIB_DIR, opts[:prompt])
  opts
end

def load_prompt(path)
  File.read(path)
      .gsub('{{CATEGORIES}}', CATEGORIES.join(', '))
      .gsub('{{TAGS}}', TAGS.join(', '))
end

def corpus_dirs(dir)
  Dir.glob(File.join(dir, '*')).select { |f| File.directory?(f) }.sort
end

def load_metadata(dir)
  path = File.join(dir, 'metadata.json')
  File.exist?(path) ? JSON.parse(File.read(path)) : {}
end

# --- Claude CLI wrapper ---

def call_claude(user_message, system_prompt: nil, model: nil)
  cmd = ['claude', '-p', '--no-session-persistence', '--tools', '']
  cmd += ['--system-prompt', system_prompt] if system_prompt
  cmd += ['--model', model] if model
  stdout, stderr, status = Open3.capture3(*cmd, stdin_data: user_message)
  unless status.success?
    return { error: "claude exited #{status.exitstatus}: #{stderr.lines.first(3).join}" }
  end
  { text: stdout }
rescue Errno::ENOENT
  { error: 'claude CLI not found on PATH' }
end

def clean_import_output(text)
  text = text.gsub(/\A```\w*\n/, '').delete_suffix("\n```")
  heading_index = text.index(/^# /)
  heading_index ? text[heading_index..].rstrip + "\n" : text.rstrip + "\n"
end

def parse_json_response(text)
  cleaned = text.strip.gsub(/\A```\w*\n/, '').delete_suffix("\n```").strip
  start_idx = cleaned.index('{')
  end_idx = cleaned.rindex('}')
  return nil unless start_idx && end_idx

  JSON.parse(cleaned[start_idx..end_idx])
rescue JSON::ParserError
  nil
end

# --- Scoring pipeline ---

def import_recipe(system_prompt, input_text)
  result = call_claude(input_text, system_prompt: system_prompt, model: 'sonnet')
  return result if result[:error]

  { text: clean_import_output(result[:text]) }
end

def judge_fidelity(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric)
  return default_fidelity_error(result[:error]) if result[:error]

  parsed = parse_json_response(result[:text])
  parsed || default_fidelity_error('JSON parse failed')
end

def judge_step_structure(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric)
  return default_step_error(result[:error]) if result[:error]

  parsed = parse_json_response(result[:text])
  parsed || default_step_error('JSON parse failed')
end

def default_fidelity_error(msg)
  { 'error' => msg, 'fidelity_score' => 0, 'detritus_score' => 0 }
end

def default_step_error(msg)
  { 'error' => msg, 'step_structure_score' => 0 }
end

def process_recipe(dir, system_prompt, fidelity_rubric, step_rubric)
  name = File.basename(dir)
  input_text = File.read(File.join(dir, 'input.txt'))
  metadata = load_metadata(dir)

  puts "[#{name}] Importing..."
  import = import_recipe(system_prompt, input_text)
  return error_scores(import[:error]) if import[:error]

  output_text = import[:text]

  puts "  [#{name}] Layer 1: parse + compat..."
  parse = Scorers::ParseChecker.check(output_text)
  compat = Scorers::SystemCompatChecker.check(output_text)

  puts "  [#{name}] Layer 2: format..."
  format = Scorers::FormatChecker.check(output_text, valid_categories: CATEGORIES,
                                                      input_text: input_text, metadata: metadata)

  puts "  [#{name}] Layer 3: fidelity judge..."
  fidelity = judge_fidelity(fidelity_rubric, input_text, output_text)

  puts "  [#{name}] Layer 4: step structure judge..."
  step = judge_step_structure(step_rubric, input_text, output_text)

  gate_pass = parse.pass && compat.pass
  agg = aggregate_score(gate_pass, format, fidelity, step)
  puts "  [#{name}] Aggregate: #{agg.round(1)}"

  { output_text: output_text,
    parse: { pass: parse.pass, details: parse.details },
    compat: { pass: compat.pass, details: compat.details },
    format: { score: (format.score * 100).round(1), checks: format.checks },
    fidelity: fidelity, step_structure: step, aggregate: agg.round(1) }
end

def error_scores(msg)
  { output_text: '', aggregate: 0.0,
    parse: { pass: false, details: { errors: [msg] } },
    compat: { pass: false, details: { errors: [msg] } },
    format: { score: 0.0, checks: [] },
    fidelity: { 'fidelity_score' => 0, 'detritus_score' => 0 },
    step_structure: { 'step_structure_score' => 0 } }
end

def aggregate_score(gate_pass, format_result, fidelity, step)
  return 0.0 unless gate_pass

  fmt = format_result.score * 100.0
  fid = (fidelity['fidelity_score'] || 0).to_f
  det = (fidelity['detritus_score'] || 0).to_f
  stp = (step['step_structure_score'] || 0).to_f
  (0.20 * fmt) + (0.50 * ((fid + det) / 2.0)) + (0.30 * stp)
end

# --- Concurrency ---

def parallel_map(items, concurrency)
  results = Array.new(items.size)
  queue = Queue.new
  items.each_with_index { |item, i| queue << [item, i] }
  concurrency.times { queue << nil }

  workers = concurrency.times.map do
    Thread.new do
      while (pair = queue.pop)
        item, index = pair
        results[index] = yield(item)
      end
    end
  end

  workers.each(&:join)
  results
end

# --- Output ---

def next_label
  existing = Dir.glob(File.join(RESULTS_DIR, 'iteration_*'))
                .map { |d| File.basename(d).delete_prefix('iteration_') }
                .select { |l| l.match?(/\A\d+\z/) }
                .map(&:to_i)
  format('%03d', (existing.max || 0) + 1)
end

def prompt_sha(path)
  `git hash-object #{path}`.strip
end

def update_state(label, avg, worst, prompt_path)
  state_path = File.join(RESULTS_DIR, 'state.json')
  state = File.exist?(state_path) ? JSON.parse(File.read(state_path)) : {
    'iterations' => [], 'best_iteration' => nil, 'best_avg' => 0.0, 'patience' => 0
  }

  state['iterations'] << {
    'label' => label, 'avg' => avg, 'worst' => worst,
    'prompt_sha' => prompt_sha(prompt_path)
  }

  if avg > state['best_avg']
    state['best_iteration'] = label
    state['best_avg'] = avg
    state['patience'] = 0
  else
    state['patience'] += 1
  end

  File.write(state_path, JSON.pretty_generate(state))
  state
end

def write_summary(iter_dir, scores, output_dir)
  lines = summary_header(iter_dir, scores)
  append_failure_details(lines, scores, output_dir)
  File.write(File.join(iter_dir, 'summary.md'), lines.join("\n"))

  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size.to_f).round(1)
  worst = scores.values.map { |s| s[:aggregate] }.min.round(1)
  [avg, worst]
end

def summary_header(iter_dir, scores)
  lines = ["# Iteration #{File.basename(iter_dir)}\n"]
  lines << '| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |'
  lines << '|--------|-------|--------|--------|----------|----------|-------|-----------|'

  scores.each do |name, data|
    p = data[:parse][:pass] ? 'PASS' : 'FAIL'
    c = data[:compat][:pass] ? 'PASS' : 'FAIL'
    f = "#{data[:format][:score]}%"
    fi = data[:fidelity]['fidelity_score'] || 0
    d = data[:fidelity]['detritus_score'] || 0
    s = data[:step_structure]['step_structure_score'] || 0
    lines << "| #{name} | #{p} | #{c} | #{f} | #{fi} | #{d} | #{s} | #{data[:aggregate]} |"
  end

  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size.to_f).round(1)
  worst = scores.values.map { |s| s[:aggregate] }.min.round(1)
  lines << '' << "**Overall:** #{avg} avg, #{worst} worst" << ''
  lines
end

def append_failure_details(lines, scores, output_dir)
  scores.each do |name, data|
    issues = collect_issues(data)
    next if issues.empty?

    lines << "### #{name} — issues"
    issues.each { |i| lines << "- #{i}" }
    append_output_snippet(lines, output_dir, name) if data[:aggregate] < 90
    lines << ''
  end
end

def collect_issues(data)
  issues = []
  issues << "PARSE: #{data[:parse][:details][:errors].join(', ')}" unless data[:parse][:pass]
  issues << "COMPAT: #{data[:compat][:details][:errors].join(', ')}" unless data[:compat][:pass]

  (data[:format][:checks] || []).each do |check|
    next if check[:pass]

    detail = check[:failures] ? " — #{Array(check[:failures]).join(', ')}" : ''
    issues << "FORMAT: #{check[:name]}#{detail}"
  end

  %w[ingredients_missing ingredients_added quantities_changed instructions_dropped
     instructions_rewritten detritus_retained prep_leaked_into_name].each do |key|
    items = data[:fidelity][key]
    next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

    issues << "FIDELITY: #{key}: #{Array(items).join(', ')}"
  end

  %w[split_issues naming_issues ownership_issues flow_issues].each do |key|
    items = data[:step_structure][key]
    next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

    issues << "STEPS: #{key}: #{Array(items).join(', ')}"
  end

  issues
end

def append_output_snippet(lines, output_dir, name)
  path = File.join(output_dir, "#{name}.md")
  return unless File.exist?(path)

  snippet = File.readlines(path).first(20).join
  lines << '' << '**Output snippet (first 20 lines):**' << '```' << snippet << '```'
end

# --- Main ---

def run_evaluation
  opts = parse_args
  opts[:label] ||= next_label
  label = opts[:label]

  puts "Corpus:      #{opts[:corpus_dir]}"
  puts "Prompt:      #{opts[:prompt_path]}"
  puts "Concurrency: #{opts[:concurrency]}"
  puts "Label:       #{label}"

  system_prompt = load_prompt(opts[:prompt_path])
  fidelity_rubric = File.read(File.join(BASE_DIR, 'scorers', 'fidelity_judge_prompt.md'))
  step_rubric = File.read(File.join(BASE_DIR, 'scorers', 'step_structure_judge_prompt.md'))

  iter_dir = File.join(RESULTS_DIR, "iteration_#{label}")
  output_dir = File.join(iter_dir, 'outputs')
  FileUtils.mkdir_p(output_dir)

  dirs = corpus_dirs(opts[:corpus_dir])
  puts "Processing #{dirs.size} recipes...\n\n"

  results = parallel_map(dirs, opts[:concurrency]) do |dir|
    process_recipe(dir, system_prompt, fidelity_rubric, step_rubric)
  end

  scores = {}
  dirs.each_with_index do |dir, i|
    name = File.basename(dir)
    File.write(File.join(output_dir, "#{name}.md"), results[i][:output_text])
    scores[name] = results[i].except(:output_text)
  end

  File.write(File.join(iter_dir, 'scores.json'), JSON.pretty_generate(scores))
  avg, worst = write_summary(iter_dir, scores, output_dir)
  state = update_state(label, avg, worst, opts[:prompt_path])

  puts "\nResults: #{iter_dir}/"
  puts "Overall: #{avg} avg, #{worst} worst"
  puts "Best: #{state['best_avg']} (iteration #{state['best_iteration']}), patience: #{state['patience']}/2"
end

run_evaluation if $PROGRAM_NAME == __FILE__
