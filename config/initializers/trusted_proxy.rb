# frozen_string_literal: true

# Loads FamilyRecipes::TrustedProxyConfig once at boot from environment
# variables (TRUSTED_PROXY_IPS, TRUSTED_HEADER_USER/_EMAIL/_NAME) and
# stashes it on Rails.configuration so ApplicationController can read
# it without touching ENV directly. An invalid CIDR in TRUSTED_PROXY_IPS
# raises at boot — fail fast on operator typos.
Rails.application.config.trusted_proxy_config = FamilyRecipes::TrustedProxyConfig.from_env
