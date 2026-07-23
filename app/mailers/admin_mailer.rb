# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  default to: "jasper@patchworklabs.org"

  def email_throttle_warning(count, date)
    @count = count
    @date = date
    @limit = Interceptors::EmailThrottleInterceptor::DAILY_LIMIT
    @remaining = @limit - @count

    mail(
      subject: "[IDP Alert] Approaching daily email limit (#{@remaining} remaining)"
    )
  end

end
