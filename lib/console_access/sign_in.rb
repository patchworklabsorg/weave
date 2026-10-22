# frozen_string_literal: true

require "socket"

module ConsoleAccess
  # Opens a ConsoleAccessRequest, shows its code, and waits until the person
  # at the console signs it in to Weave as themselves. Returns that user.
  class SignIn
    POLL_INTERVAL = 2

    def initialize(kind:, output: $stdout, host: Socket.gethostname, sleeper: ->(seconds) { sleep(seconds) })
      @kind = kind
      @output = output
      @host = host
      @sleeper = sleeper
    end

    def await!
      request = ConsoleAccessRequest.open!(kind: @kind, host: @host)
      @output.puts <<~TEXT

        Weave records who uses this console. Sign in to Weave as yourself, open
        #{Weave.url}/admin/console_access and enter this code:

            #{request.code}

        The code expires in #{ConsoleAccessRequest::EXPIRATION.inspect}. Press Ctrl-C to cancel.
      TEXT

      loop do
        @sleeper.call(POLL_INTERVAL)
        ConsoleAccessRequest.uncached { request.reload }
        user = request.claim!
        return user if user
        raise Error, "The console was marked as not yours." if request.rejected?
        raise Error, "The code expired. Start the console again." if request.expired?
        raise Error, "The code cannot be used. Start the console again." if request.confirmed?
      end
    end

  end
end
