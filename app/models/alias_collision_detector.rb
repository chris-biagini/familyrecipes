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
    canonical_names = catalog_data.keys.each_with_object({}) { |n, h| h[n.downcase] = n }
    alias_owners = {}
    collisions = []

    catalog_data.each do |name, entry|
      (entry['aliases'] || []).each do |alias_name|
        lowered = alias_name.downcase

        if canonical_names.key?(lowered) && canonical_names[lowered] != name
          collisions << "#{name}: alias '#{alias_name}' matches canonical entry '#{canonical_names[lowered]}'"
        elsif alias_owners.key?(lowered)
          collisions << "#{name}: alias '#{alias_name}' also claimed by '#{alias_owners[lowered]}'"
        else
          alias_owners[lowered] = name
        end
      end
    end

    collisions
  end
end
