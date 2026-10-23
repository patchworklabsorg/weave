# frozen_string_literal: true

# Checks config/roles.yml at boot (see RoleRegistry). A bad file raises
# RoleRegistry::ConfigError, so Weave does not start with a rule that nobody
# checks. In development the check runs again after each code reload.
Rails.application.config.to_prepare do
  RoleRegistry.reset!
  RoleRegistry.validate!
end
