# frozen_string_literal: true

Rails.application.configure do
  console do
    # Staging runs with RAILS_ENV=production, so the Rails prompt would read
    # weave(prod). Name the deployment instead (see Weave.staging?). Rails
    # loads IRBConsole only after this block, so load it here.
    if Weave.staging?
      require "rails/commands/console/irb_console"
      Rails::Console::IRBConsole.prepend(Module.new do
        def colorized_env = IRB::Color.colorize("staging", [:YELLOW])
      end)
    end

    # The permanent log of privileged attributes names the console user (see
    # PrivilegedChangeActor). Console1984 asks for the name in production.
    username = (Console1984.supervisor.current_username if Console1984.running_protected_environment?)
    PrivilegedChangeActor.set!(label: "console #{username.presence || ENV.fetch('USER', 'unknown')}")

    # In production and staging the person signed the console in (see
    # ConsoleAccess::UsernameResolver), so PaperTrail records them. Never ask
    # on stdin: a save would wait inside its transaction for an answer.
    signed_in = Rails.application.config.console1984.username_resolver.try(:user)
    PaperTrail.request.whodunnit = signed_in&.id || "console #{ENV.fetch('USER', 'unknown')}"
  end
end

# Trying to update a bunch of records and need to change the edit history per record? Try this out:

# PaperTrail.request(whodunnit: 'Dorian Marié') do
#   widget.update name: 'Wibble'
# end

# See https://github.com/paper-trail-gem/paper_trail#setting-whodunnit-temporarily for more details
