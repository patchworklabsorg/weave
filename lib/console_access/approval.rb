# frozen_string_literal: true

require "socket"

module ConsoleAccess
  # Opens a ConsoleAccessRequest, shows its code, and waits until a superadmin
  # approves it in Weave. Returns the approver.
  class Approval
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

        This console needs your approval in Weave. Sign in as yourself, open
        #{Weave.url}/admin/console_access and enter this code:

            #{request.code}

        The code expires in #{ConsoleAccessRequest::EXPIRATION.inspect}. Press Ctrl-C to cancel.
      TEXT

      loop do
        @sleeper.call(POLL_INTERVAL)
        ConsoleAccessRequest.uncached { request.reload }
        approver = request.claim!
        return notify(request, approver) if approver
        raise Error, "The console request was denied." if request.denied?
        raise Error, "The console request expired. Start the console again." if request.expired?
        raise Error, "The console request cannot be used. Start the console again." if request.approved?
      end
    end

    private

    # The approver learns about every console opened under their name, so an
    # approval written into the database by hand does not go unseen. The mail
    # goes out now, not through the job queue, and the console stays closed
    # if it cannot be sent.
    def notify(request, approver)
      ConsoleAccessMailer.opened(request).deliver_now
      approver
    rescue => e
      raise Error, "Weave could not send the approval email (#{e.class}), so the console stays closed."
    end

  end
end
