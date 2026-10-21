# frozen_string_literal: true

module ConsoleAccess
  # The Console1984 username resolver for `bin/rails console`. Console1984 asks
  # it once, when a session starts in a protected environment.
  class UsernameResolver
    def current
      ConsoleAccess.username_for(Approval.new(kind: "console").await!)
    rescue Error, Interrupt => e
      abort(e.message.presence || "Cancelled.")
    end

  end
end
