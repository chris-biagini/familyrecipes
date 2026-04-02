# frozen_string_literal: true

# Introspects ActiveRecord models and the database schema for:
# 1. Missing foreign keys — belongs_to without DB FK constraint
# 2. Missing indexes — foreign key columns without indexes
# 3. Orphaned records — rows referencing nonexistent parents
#
# Missing FKs and indexes are warnings; orphaned records are a hard fail
# (configurable via config/release_audit.yml).

namespace :release do
  namespace :audit do
    desc 'Check database schema integrity'
    task schema: :environment do
      config = YAML.load_file(Rails.root.join('config/release_audit.yml'))
      results = { missing_fks: [], missing_indexes: [], orphans: [] }

      check_foreign_keys(results)
      check_missing_indexes(results)
      check_orphaned_records(results)

      print_schema_summary(results, config)

      if config.dig('schema', 'fail_on_orphaned_records') && results[:orphans].any?
        abort "\nSchema integrity check failed — orphaned records found."
      end
    end
  end
end

def existing_fk_set
  connection = ActiveRecord::Base.connection
  connection.tables.flat_map do |table|
    connection.foreign_keys(table).map { |fk| [table, fk.column] }
  end.to_set
end

def check_foreign_keys(results)
  fks = existing_fk_set

  ar_models.each do |model|
    model.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.options[:polymorphic]

      table = model.table_name
      column = assoc.foreign_key.to_s
      next if fks.include?([table, column])

      results[:missing_fks] << "#{table}.#{column} (#{model.name} belongs_to #{assoc.name})"
    end
  end
end

def indexed_column_set
  connection = ActiveRecord::Base.connection
  set = connection.tables.flat_map do |table|
    connection.indexes(table).flat_map { |idx| idx.columns.map { |col| [table, col] } }
  end.to_set

  # Primary keys are always indexed but not listed in connection.indexes
  connection.tables.each { |table| set.add([table, 'id']) }
  set
end

def check_missing_indexes(results)
  indexed = indexed_column_set

  ar_models.each do |model|
    model.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.options[:polymorphic]

      table = model.table_name
      column = assoc.foreign_key.to_s
      next if indexed.include?([table, column])

      results[:missing_indexes] << "#{table}.#{column} (foreign key for #{assoc.name})"
    end
  end
end

def orphan_count_for(assoc, model)
  child_table = model.table_name
  foreign_key = assoc.foreign_key.to_s
  parent_table = assoc.klass.table_name
  primary_key = assoc.association_primary_key.to_s

  sql = <<~SQL.squish
    SELECT COUNT(*) FROM #{child_table}
    WHERE #{foreign_key} IS NOT NULL
      AND #{foreign_key} NOT IN (SELECT #{primary_key} FROM #{parent_table})
  SQL

  ActiveRecord::Base.connection.select_value(sql).to_i
end

def check_orphaned_records(results)
  ar_models.each do |model|
    model.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.options[:polymorphic]
      next if assoc.options[:optional]

      count = orphan_count_for(assoc, model)
      next unless count.positive?

      parent_table = assoc.klass.table_name
      results[:orphans] << "#{model.table_name}.#{assoc.foreign_key} → #{parent_table}: #{count} orphaned row(s)"
    end
  end
end

def ar_models
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.reject { |m| m.abstract_class? || m.table_name.blank? }
end

def print_schema_summary(results, config)
  print_missing_fks(results[:missing_fks], config)
  print_missing_indexes(results[:missing_indexes])
  print_orphans(results[:orphans])
  print_totals(results)
end

def print_missing_fks(missing_fks, config)
  return unless missing_fks.any?

  puts "\nMissing foreign keys (#{missing_fks.size}):"
  missing_fks.each { |fk| puts "  #{fk}" }
  puts "  (warning only — fail_on_missing_fk: false)\n" unless config.dig('schema', 'fail_on_missing_fk')
end

def print_missing_indexes(missing_indexes)
  return unless missing_indexes.any?

  puts "\nMissing indexes (#{missing_indexes.size}):"
  missing_indexes.each { |idx| puts "  #{idx}" }
  puts "  (warning only — consider adding indexes for query performance)\n"
end

def print_orphans(orphans)
  return unless orphans.any?

  puts "\nOrphaned records (#{orphans.size}):"
  orphans.each { |o| puts "  #{o}" }
end

def print_totals(results)
  fk_count = results[:missing_fks].size
  idx_count = results[:missing_indexes].size
  orphan_count = results[:orphans].size

  puts "\nSchema FKs: #{fk_count} missing #{fk_count.zero? ? '✓' : '(warning)'}"
  puts "Schema indexes: #{idx_count} missing #{idx_count.zero? ? '✓' : '(warning)'}"
  puts "Orphaned records: #{orphan_count} #{orphan_count.zero? ? '✓' : '— FAIL'}"
end
