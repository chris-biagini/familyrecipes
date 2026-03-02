# frozen_string_literal: true

# Computes a short SHA-256 digest of favicon.svg at boot time for cache-busting
# PWA icon URLs. ApplicationController exposes it as a helper method so views
# and the manifest can append ?v=<hash> to /icons/ paths.
Rails.configuration.icon_version = begin
  svg = Rails.root.join('app/assets/images/favicon.svg')
  svg.exist? ? Digest::SHA256.file(svg).hexdigest[0, 8] : '0'
end
