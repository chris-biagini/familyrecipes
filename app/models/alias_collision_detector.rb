# frozen_string_literal: true

# Detects alias collisions across a set of ingredient catalog entries.
# Used by catalog:sync to report cross-entry alias conflicts without
# blocking the sync. Checks alias-vs-alias and alias-vs-canonical-name.
#
# Collaborators:
# - catalog_sync.rake: calls detect() after loading YAML
# - CatalogSyncTest: unit tests collision detection logic
class AliasCollisionDetector
  def self.detect(catalog_data)
    canonical_names = catalog_data.keys.index_by(&:downcase)
    alias_owners = {}

    catalog_data.flat_map do |name, entry|
      check_aliases(name, entry['aliases'] || [], canonical_names, alias_owners)
    end
  end

  def self.check_aliases(name, aliases, canonical_names, alias_owners)
    aliases.filter_map do |alias_name|
      lowered = alias_name.downcase

      if canonical_names.key?(lowered) && canonical_names[lowered] != name
        "#{name}: alias '#{alias_name}' matches canonical entry '#{canonical_names[lowered]}'"
      elsif alias_owners.key?(lowered)
        "#{name}: alias '#{alias_name}' also claimed by '#{alias_owners[lowered]}'"
      else
        alias_owners[lowered] = name
        nil
      end
    end
  end
  private_class_method :check_aliases
end
