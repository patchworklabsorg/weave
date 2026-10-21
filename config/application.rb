# frozen_string_literal: true

require_relative "boot"

require "rails/all"
require_relative "../lib/credentials_paths"
require_relative "../lib/weave"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# app name should be InThisCase
module Weave
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Solid Queue writes to its own database, so a job enqueued inside a
    # transaction on the primary database was visible to workers before that
    # transaction committed. A worker could then run it before its records
    # existed (ActiveJob::DeserializationError). Rails 8.1 defaults to this.
    config.active_job.enqueue_after_transaction_commit = true

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # credentials_paths.rb and weave.rb are required by hand above, before
    # Zeitwerk exists. config/initializers/flipper.rb requires feature_flags by
    # hand, because an initializer cannot use a reloadable constant. So does
    # config/initializers/console_access.rb for console_access.
    config.autoload_lib(ignore: %w[assets tasks credentials_paths.rb weave.rb feature_flags.rb feature_flags console_access.rb console_access])

    # Keep the credentials file and the key that opens it in lockstep; Rails
    # resolves them independently and will otherwise pair a per-environment
    # file with config/master.key. WEAVE_ENV=staging selects staging's own pair.
    # See lib/credentials_paths.rb.
    config.credentials.content_path, config.credentials.key_path =
      CredentialsPaths.resolve(root: Rails.root, env: Rails.env, deployment: Weave.credentials_deployment)

    config.mission_control.jobs.base_controller_class = "Admin::BaseController"
    config.mission_control.jobs.http_basic_auth_enabled = false
    config.audits1984.base_controller_class = "Admin::BaseController"
    config.console1984.incinerate = false
    # Audit records write through their own connection pool. See
    # app/models/console_audit_record.rb.
    config.console1984.base_record_class = "::ConsoleAuditRecord"
    config.console1984.production_data_warning = "You have access to production data here. That's a big deal. As part of our promise to keep customer data safe and private, we audit the commands you type here. Let's get started!"
    config.console1984.enter_unprotected_encryption_mode_warning = "Ok! You have access to encrypted information now. We pay extra close attention to any commands entered while you have this access. You can go back to protected mode with 'encrypt!' WARNING: Make sure you don't save objects that were loaded while in protected mode, as this can result in saving the encrypted texts."
    config.console1984.enter_protected_mode_warning	= "Great! You are back in protected mode. When we audit, we may reach out for a conversation about the commands you entered. What went well? Did you solve the problem without accessing personal data?"
    # config/initializers/console_access.rb sets the username resolver: a
    # superadmin approves each console in Weave. There is no name prompt.
    config.console1984.protected_environments = %i[production staging]

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

  end
end

# bin/rails dbconsole opens the audited SQL console in a protected environment.
require_relative "../lib/console_access/dbconsole" if defined?(Rails::DBConsole)
