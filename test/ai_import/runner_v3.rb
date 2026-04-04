#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Import prompt evaluation runner (v3). Standalone script — no Rails boot.
# Uses `claude -p` instead of direct API calls — runs on Max plan tokens.
#
# Supports two modes, detected from the prompt filename:
# - Faithful mode (default): scores text fidelity to source
# - Expert mode (prompt contains "expert"): scores outcome fidelity + style
#
# Faithful aggregate: 0.20 * format + 0.50 * ((fidelity + detritus) / 2) + 0.30 * steps
# Expert aggregate:   0.10 * format + 0.40 * ((outcome_fid + detritus) / 2) + 0.25 * steps + 0.25 * style
#
# Usage:
#   ruby test/ai_import/runner_v3.rb [label]
#   ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_expert.md [label]
#   ruby test/ai_import/runner_v3.rb --corpus=corpus_v3 [label]
#   ruby test/ai_import/runner_v3.rb --concurrency=5 [label]
#
# Collaborators:
# - claude CLI (`claude -p`) for import (Sonnet) and judging (default model)
# - Scorers::ParseChecker, FormatChecker, SystemCompatChecker for algorithmic checks
# - fidelity_judge_prompt.md / outcome_fidelity_judge_prompt.md for fidelity judging
# - step_structure_judge_prompt.md for step structure judging
# - style_judge_prompt.md for expert style judging (expert mode only)

require 'json'
require 'fileutils'
require 'open3'
require 'timeout'

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

FIDELITY_SCHEMA = {
  type: 'object',
  properties: {
    ingredients_missing: { type: 'array', items: { type: 'string' } },
    ingredients_added: { type: 'array', items: { type: 'string' } },
    quantities_changed: { type: 'array', items: { type: 'string' } },
    instructions_dropped: { type: 'array', items: { type: 'string' } },
    instructions_rewritten: { type: 'array', items: { type: 'string' } },
    detritus_retained: { type: 'array', items: { type: 'string' } },
    prep_leaked_into_name: { type: 'array', items: { type: 'string' } },
    fidelity_score: { type: 'integer' },
    detritus_score: { type: 'integer' }
  },
  required: %w[fidelity_score detritus_score]
}.freeze

OUTCOME_FIDELITY_SCHEMA = {
  type: 'object',
  properties: {
    ingredients_missing: { type: 'array', items: { type: 'string' } },
    ingredients_added: { type: 'array', items: { type: 'string' } },
    quantities_changed: { type: 'array', items: { type: 'string' } },
    technique_lost: { type: 'array', items: { type: 'string' } },
    outcome_affected: { type: 'array', items: { type: 'string' } },
    detritus_retained: { type: 'array', items: { type: 'string' } },
    outcome_fidelity_score: { type: 'integer' },
    detritus_score: { type: 'integer' }
  },
  required: %w[outcome_fidelity_score detritus_score]
}.freeze

STYLE_SCHEMA = {
  type: 'object',
  properties: {
    voice_score: { type: 'integer' },
    voice_issues: { type: 'array', items: { type: 'string' } },
    condensation_score: { type: 'integer' },
    condensation_issues: { type: 'array', items: { type: 'string' } },
    specificity_score: { type: 'integer' },
    specificity_issues: { type: 'array', items: { type: 'string' } },
    title_score: { type: 'integer' },
    title_issues: { type: 'array', items: { type: 'string' } },
    description_score: { type: 'integer' },
    description_issues: { type: 'array', items: { type: 'string' } },
    prose_score: { type: 'integer' },
    prose_issues: { type: 'array', items: { type: 'string' } },
    footer_score: { type: 'integer' },
    footer_issues: { type: 'array', items: { type: 'string' } },
    economy_score: { type: 'integer' },
    economy_issues: { type: 'array', items: { type: 'string' } },
    style_score: { type: 'integer' }
  },
  required: %w[style_score]
}.freeze

STEP_STRUCTURE_SCHEMA = {
  type: 'object',
  properties: {
    split_decision: { type: 'string' },
    expected_decision: { type: 'string' },
    split_issues: { type: 'array', items: { type: 'string' } },
    naming_issues: { type: 'array', items: { type: 'string' } },
    ownership_issues: { type: 'array', items: { type: 'string' } },
    flow_issues: { type: 'array', items: { type: 'string' } },
    step_structure_score: { type: 'integer' }
  },
  required: %w[step_structure_score]
}.freeze

EXPERT_STEP_STRUCTURE_SCHEMA = {
  type: 'object',
  properties: {
    split_decision: { type: 'string' },
    phase_design_issues: { type: 'array', items: { type: 'string' } },
    disentanglement_issues: { type: 'array', items: { type: 'string' } },
    ownership_issues: { type: 'array', items: { type: 'string' } },
    naming_issues: { type: 'array', items: { type: 'string' } },
    step_structure_score: { type: 'integer' }
  },
  required: %w[step_structure_score]
}.freeze

# --- CLI ---

def parse_args
  opts = { corpus: 'corpus_v3', prompt: 'ai_import_prompt_faithful.md', concurrency: 5, label: nil }

  ARGV.each do |arg|
    case arg
    when /\A--corpus=(.+)/ then opts[:corpus] = Regexp.last_match(1)
    when /\A--prompt=(.+)/ then opts[:prompt] = Regexp.last_match(1)
    when /\A--concurrency=(\d+)/ then opts[:concurrency] = Regexp.last_match(1).to_i
    else opts[:label] = arg
    end
  end

  opts[:corpus_dir] = File.join(BASE_DIR, opts[:corpus])
  opts[:prompt_path] = File.join(LIB_DIR, opts[:prompt])
  opts
end

def expert_mode?(opts)
  opts[:prompt].include?('expert')
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

def call_claude(user_message, system_prompt: nil, model: nil, timeout: 600, json_schema: nil)
  cmd = ['claude', '-p', '--no-session-persistence', '--tools', '']
  cmd += ['--system-prompt', system_prompt] if system_prompt
  cmd += ['--model', model] if model
  if json_schema
    cmd += ['--output-format', 'json']
    cmd += ['--json-schema', JSON.generate(json_schema)]
  end
  stdout, stderr, status = Timeout.timeout(timeout) do
    Open3.capture3(*cmd, stdin_data: user_message)
  end
  return { error: "claude exited #{status.exitstatus}: #{stderr.lines.first(3).join}" } unless status.success?

  if json_schema
    parsed = parse_structured_response(stdout)
    return parsed.is_a?(Hash) && parsed['error'] ? parsed : { json: parsed }
  end
  { text: stdout }
rescue Timeout::Error
  { error: "claude timed out after #{timeout}s" }
rescue Errno::ENOENT
  { error: 'claude CLI not found on PATH' }
end

def parse_structured_response(stdout)
  envelope = JSON.parse(stdout)
  structured = envelope['structured_output']
  return structured if structured.is_a?(Hash)

  { 'error' => 'no structured_output in response' }
rescue JSON::ParserError => error
  { 'error' => "envelope JSON parse failed: #{error.message}" }
end

def clean_import_output(text)
  text = text.sub(/\A```\w*\n/, '').delete_suffix("\n```")
  heading_index = text.index(/^# /)
  heading_index ? "#{text[heading_index..].rstrip}\n" : "#{text.rstrip}\n"
end

# --- Scoring pipeline ---

def import_recipe(system_prompt, input_text)
  result = call_claude(input_text, system_prompt: system_prompt, model: 'sonnet')
  return result if result[:error]

  { text: clean_import_output(result[:text]) }
end

def judge_fidelity(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric, json_schema: FIDELITY_SCHEMA)
  return default_fidelity_error(result[:error]) if result[:error]

  result[:json] || default_fidelity_error('structured response missing')
end

def judge_step_structure(rubric, original, output, schema: STEP_STRUCTURE_SCHEMA)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric, json_schema: schema)
  return default_step_error(result[:error]) if result[:error]

  result[:json] || default_step_error('structured response missing')
end

def judge_outcome_fidelity(rubric, original, output)
  user_msg = "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
  result = call_claude(user_msg, system_prompt: rubric, json_schema: OUTCOME_FIDELITY_SCHEMA)
  return default_outcome_fidelity_error(result[:error]) if result[:error]

  result[:json] || default_outcome_fidelity_error('structured response missing')
end

def judge_style(rubric, output)
  result = call_claude(output, system_prompt: rubric, json_schema: STYLE_SCHEMA)
  return default_style_error(result[:error]) if result[:error]

  result[:json] || default_style_error('structured response missing')
end

def default_fidelity_error(msg)
  { 'error' => msg, 'fidelity_score' => 0, 'detritus_score' => 0 }
end

def default_outcome_fidelity_error(msg)
  { 'error' => msg, 'outcome_fidelity_score' => 0, 'detritus_score' => 0 }
end

def default_step_error(msg)
  { 'error' => msg, 'step_structure_score' => 0 }
end

def default_style_error(msg)
  { 'error' => msg, 'style_score' => 0 }
end

def process_recipe(dir, system_prompt, rubrics, opts)
  name = File.basename(dir)
  input_text = File.read(File.join(dir, 'input.txt'))
  metadata = load_metadata(dir)
  expert = expert_mode?(opts)
  metadata['expected_steps'] = metadata['expected_steps_expert'] if expert && metadata.key?('expected_steps_expert')

  puts "[#{name}] Importing..."
  import = import_recipe(system_prompt, input_text)
  return error_scores(import[:error], expert: expert) if import[:error]

  output_text = import[:text]

  puts "  [#{name}] Layer 1: parse + compat..."
  parse = Scorers::ParseChecker.check(output_text)
  compat = Scorers::SystemCompatChecker.check(output_text)

  puts "  [#{name}] Layer 2: format..."
  format = Scorers::FormatChecker.check(output_text, valid_categories: CATEGORIES,
                                                     valid_tags: TAGS,
                                                     input_text: input_text, metadata: metadata)

  puts "  [#{name}] Layer 3: fidelity judge..."
  fidelity = if expert
               judge_outcome_fidelity(rubrics[:fidelity], input_text, output_text)
             else
               judge_fidelity(rubrics[:fidelity], input_text, output_text)
             end

  puts "  [#{name}] Layer 4: step structure judge..."
  step_schema = expert ? EXPERT_STEP_STRUCTURE_SCHEMA : STEP_STRUCTURE_SCHEMA
  step = judge_step_structure(rubrics[:step], input_text, output_text, schema: step_schema)

  style = nil
  if expert
    puts "  [#{name}] Layer 5: style judge..."
    style = judge_style(rubrics[:style], output_text)
  end

  gate_pass = parse.pass && compat.pass
  agg = aggregate_score(gate_pass, format, fidelity, step, style, expert: expert)
  puts "  [#{name}] Aggregate: #{agg.round(1)}"

  result = { output_text: output_text,
             parse: { pass: parse.pass, details: parse.details },
             compat: { pass: compat.pass, details: compat.details },
             format: { score: (format.score * 100).round(1), checks: format.checks },
             fidelity: fidelity, step_structure: step, aggregate: agg.round(1) }
  result[:style] = style if style
  result
end

def error_scores(msg, expert: false)
  result = { output_text: '', aggregate: 0.0,
             parse: { pass: false, details: { errors: [msg] } },
             compat: { pass: false, details: { errors: [msg] } },
             format: { score: 0.0, checks: [] },
             step_structure: { 'step_structure_score' => 0 } }
  if expert
    result[:fidelity] = { 'outcome_fidelity_score' => 0, 'detritus_score' => 0 }
    result[:style] = { 'style_score' => 0 }
  else
    result[:fidelity] = { 'fidelity_score' => 0, 'detritus_score' => 0 }
  end
  result
end

def aggregate_score(gate_pass, format_result, fidelity, step, style = nil, expert: false) # rubocop:disable Metrics/ParameterLists
  return 0.0 unless gate_pass

  fmt = format_result.score * 100.0
  det = (fidelity['detritus_score'] || 0).to_f
  stp = (step['step_structure_score'] || 0).to_f

  if expert
    fid = (fidelity['outcome_fidelity_score'] || 0).to_f
    sty = (style&.dig('style_score') || 0).to_f
    (0.10 * fmt) + (0.40 * ((fid + det) / 2.0)) + (0.25 * stp) + (0.25 * sty)
  else
    fid = (fidelity['fidelity_score'] || 0).to_f
    (0.20 * fmt) + (0.50 * ((fid + det) / 2.0)) + (0.30 * stp)
  end
end

# --- Concurrency ---

def parallel_map(items, concurrency)
  results = Array.new(items.size)
  queue = Queue.new
  items.each_with_index { |item, i| queue << [item, i] }
  concurrency.times { queue << nil }

  workers = Array.new(concurrency) do
    Thread.new do
      while (pair = queue.pop)
        item, index = pair
        results[index] = begin
          yield(item)
        rescue StandardError => error
          error_scores("Unhandled error: #{error.message}")
        end
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
                .grep(/\A\d+\z/)
                .map(&:to_i)
  format('%03d', (existing.max || 0) + 1)
end

def prompt_sha(path)
  stdout, _status = Open3.capture2('git', 'hash-object', path)
  stdout.strip
end

def update_state(label, avg, worst, prompt_path)
  state_path = File.join(RESULTS_DIR, 'state.json')
  state = if File.exist?(state_path)
            JSON.parse(File.read(state_path))
          else
            {
              'iterations' => [], 'best_iteration' => nil, 'best_avg' => 0.0, 'patience' => 0
            }
          end

  state['iterations'] << {
    'label' => label, 'avg' => avg, 'worst' => worst,
    'prompt_sha' => prompt_sha(prompt_path),
    'prompt_lines' => File.readlines(prompt_path).size
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

def compute_overall(scores)
  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size.to_f).round(1)
  worst = scores.values.map { |s| s[:aggregate] }.min.round(1) # rubocop:disable Rails/Pluck -- no Rails
  [avg, worst]
end

def write_summary(iter_dir, scores, output_dir, expert: false)
  avg, worst = compute_overall(scores)
  lines = summary_table(iter_dir, scores, avg, worst, expert: expert)
  append_failure_details(lines, scores, output_dir)
  File.write(File.join(iter_dir, 'summary.md'), lines.join("\n"))
  [avg, worst]
end

def summary_table(iter_dir, scores, avg, worst, expert: false)
  lines = ["# Iteration #{File.basename(iter_dir)}\n"]
  if expert
    lines << '| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Style | Aggregate |'
    lines << '|--------|-------|--------|--------|----------|----------|-------|-------|-----------|'
  else
    lines << '| Recipe | Parse | Compat | Format | Fidelity | Detritus | Steps | Aggregate |'
    lines << '|--------|-------|--------|--------|----------|----------|-------|-----------|'
  end

  scores.each do |name, data|
    p = data[:parse][:pass] ? 'PASS' : 'FAIL'
    c = data[:compat][:pass] ? 'PASS' : 'FAIL'
    f = "#{data[:format][:score]}%"
    fi = data[:fidelity][expert ? 'outcome_fidelity_score' : 'fidelity_score'] || 0
    d = data[:fidelity]['detritus_score'] || 0
    s = data[:step_structure]['step_structure_score'] || 0
    if expert
      sty = data[:style]&.dig('style_score') || 0
      lines << "| #{name} | #{p} | #{c} | #{f} | #{fi} | #{d} | #{s} | #{sty} | #{data[:aggregate]} |"
    else
      lines << "| #{name} | #{p} | #{c} | #{f} | #{fi} | #{d} | #{s} | #{data[:aggregate]} |"
    end
  end

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
     instructions_rewritten detritus_retained prep_leaked_into_name
     technique_lost outcome_affected].each do |key|
    items = data[:fidelity][key]
    next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

    outcome_keys = %w[technique_lost outcome_affected]
    label = outcome_keys.include?(key) ? 'OUTCOME' : 'FIDELITY'
    issues << "#{label}: #{key}: #{Array(items).join(', ')}"
  end

  %w[split_issues naming_issues ownership_issues flow_issues
     phase_design_issues disentanglement_issues].each do |key|
    items = data[:step_structure][key]
    next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

    issues << "STEPS: #{key}: #{Array(items).join(', ')}"
  end

  if data[:style]
    %w[voice_issues condensation_issues specificity_issues title_issues
       description_issues prose_issues footer_issues economy_issues].each do |key|
      items = data[:style][key]
      next if items.nil? || (items.respond_to?(:empty?) && items.empty?)

      issues << "STYLE: #{key.delete_suffix('_issues')}: #{Array(items).join(', ')}"
    end
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
  mode_dir = File.join(BASE_DIR, 'scorers', expert_mode?(opts) ? 'expert' : 'faithful')
  fidelity_prompt = expert_mode?(opts) ? 'outcome_fidelity_judge_prompt.md' : 'fidelity_judge_prompt.md'
  rubrics = {
    fidelity: File.read(File.join(mode_dir, fidelity_prompt)),
    step: File.read(File.join(mode_dir, 'step_structure_judge_prompt.md'))
  }
  rubrics[:style] = File.read(File.join(mode_dir, 'style_judge_prompt.md')) if expert_mode?(opts)

  iter_dir = File.join(RESULTS_DIR, "iteration_#{label}")
  output_dir = File.join(iter_dir, 'outputs')
  FileUtils.mkdir_p(output_dir)

  dirs = corpus_dirs(opts[:corpus_dir])
  puts "Processing #{dirs.size} recipes...\n\n"

  results = parallel_map(dirs, opts[:concurrency]) do |dir|
    process_recipe(dir, system_prompt, rubrics, opts)
  end

  scores = {}
  dirs.each_with_index do |dir, i|
    name = File.basename(dir)
    File.write(File.join(output_dir, "#{name}.md"), results[i][:output_text])
    scores[name] = results[i].except(:output_text)
  end

  File.write(File.join(iter_dir, 'scores.json'), JSON.pretty_generate(scores))
  avg, worst = write_summary(iter_dir, scores, output_dir, expert: expert_mode?(opts))
  state = update_state(label, avg, worst, opts[:prompt_path])

  puts "\nResults: #{iter_dir}/"
  puts "Overall: #{avg} avg, #{worst} worst"
  puts "Best: #{state['best_avg']} (iteration #{state['best_iteration']}), patience: #{state['patience']}/2"
end

run_evaluation if $PROGRAM_NAME == __FILE__
