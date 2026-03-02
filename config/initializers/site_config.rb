# frozen_string_literal: true

# Loads site-wide copy (title, homepage heading/subtitle, GitHub URL) from
# config/site.yml into Rails.configuration.site. Consumed by LandingController,
# HomepageController, PwaController, and the application layout.
Rails.configuration.site = Rails.application.config_for(:site)
