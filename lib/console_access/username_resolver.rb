# frozen_string_literal: true

module ConsoleAccess
  # The Console1984 username resolver for `bin/rails console`. Console1984 asks
  # it when a session starts in a protected environment.
  #
  # Console1984::QueryAuditor also asks it, in every process, if Rails sends a
  # "query.rails" event. Rails 8.1 does not, but outside a console this returns
  # nil (Console1984 then writes "unknown") so a server never waits for a
  # sign-in.
  class UsernameResolver
    # The person who signed the console in, once current has run. PaperTrail
    # records their changes under them (see config/initializers/console.rb).
    attr_reader :user

    def current
      return unless defined?(Rails::Console)

      @current ||= begin
        @user = SignIn.new(kind: "console").await!
        ConsoleAccess.username_for(@user)
      end
    rescue Error, Interrupt => e
      # A console without a sign-in must not open.
      warn(e.message.presence || "Cancelled.")
      raise SystemExit.new(false)
    end

  end
end
