# frozen_string_literal: true

# Tells a superadmin that a production console opened under their name. See
# docs/CONSOLE_ACCESS.md.
class ConsoleAccessMailer < ApplicationMailer
  def opened(console_request)
    @console_request = console_request
    @user = console_request.decided_by
    @console = console_request.kind == "sql" ? "SQL console" : "Rails console"
    @audits_url = "#{Weave.url}/admin/console"

    mail(to: @user.email, subject: env_subject("A #{@console} opened under your name"))
  end

end
