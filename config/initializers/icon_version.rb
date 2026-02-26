# frozen_string_literal: true

Rails.configuration.icon_version = begin
  svg = Rails.root.join('app/assets/images/favicon.svg')
  svg.exist? ? Digest::SHA256.file(svg).hexdigest[0, 8] : '0'
end
