# frozen_string_literal: true

# Enforces Kitchen-scoped tenancy globally. With require_tenant: true, any
# query on a tenant-scoped model without an active tenant raises — preventing
# accidental cross-kitchen data leaks. Controllers set the tenant via
# set_current_tenant_through_filter; ActionCable wraps manually with
# ActsAsTenant.with_tenant.
ActsAsTenant.configure do |config|
  config.require_tenant = true
end
