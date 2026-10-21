# frozen_string_literal: true

# Production consoles that a superadmin approves in Weave, so every Console1984
# session names a real, signed-in person. See docs/CONSOLE_ACCESS.md.
#
# Not autoloaded: config/initializers/console_access.rb requires it, because
# Console1984 needs the username resolver during boot.
module ConsoleAccess
  class Error < StandardError; end

  # The text of a Console1984 username: the person's name and PWL id. The PWL
  # id is also the employeeID of the person's AD account.
  def self.username_for(user) = "#{user.full_name} (#{user.p_id})"

  def self.protected_environment?(env = Rails.env)
    Array(Rails.application.config.console1984.protected_environments).map(&:to_s).include?(env.to_s)
  end
end

require_relative "console_access/approval"
require_relative "console_access/username_resolver"
require_relative "console_access/sql_console"
