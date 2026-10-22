# frozen_string_literal: true

# In a protected environment, a Rails console waits until the person who
# started it signs it in to Weave, and Console1984 records the session under
# that person. See
# docs/CONSOLE_ACCESS.md.
require Rails.root.join("lib/console_access").to_s

Rails.application.config.console1984.username_resolver = ConsoleAccess::UsernameResolver.new
