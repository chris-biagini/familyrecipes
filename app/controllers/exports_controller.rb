# frozen_string_literal: true

# Streams a ZIP archive of all kitchen data (recipes, Quick Bites, catalog
# overrides) as a file download. Thin adapter over ExportService.
#
# - ExportService: builds the ZIP binary in memory
# - Authentication concern: require_membership gates access to members only
# - Kitchen: tenant container whose data is exported
class ExportsController < ApplicationController
  before_action :require_membership

  def show
    zip_data = ExportService.call(kitchen: current_kitchen)
    filename = ExportService.filename(kitchen: current_kitchen)

    send_data zip_data, filename: filename, type: 'application/zip', disposition: :attachment
  end
end
