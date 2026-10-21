# frozen_string_literal: true

require "active_record/connection_adapters/postgresql_adapter"
require_relative "../console_access"

module ConsoleAccess
  # In a protected environment, `bin/rails dbconsole` opens the audited
  # ConsoleAccess::SqlConsole instead of psql. Other environments keep psql.
  #
  # config/application.rb requires this file only when the dbconsole command
  # runs. Rails::DBConsole loads the application and then calls this adapter
  # method, so the environment is not loaded yet when it is called.
  module Dbconsole
    def dbconsole(config, options = {})
      return super unless ConsoleAccess.protected_environment?

      Rails.application.require_environment!
      ConsoleAccess::SqlConsole.new(db_config: config).start
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.singleton_class.prepend(ConsoleAccess::Dbconsole)
