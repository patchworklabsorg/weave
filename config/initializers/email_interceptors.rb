# frozen_string_literal: true

# Register email interceptors
Rails.application.config.to_prepare do
  # First, so recipients it drops never count against the daily throttle. It is
  # a no-op unless the mail_allowlist credential or WEAVE_ENV=staging is set.
  ActionMailer::Base.register_interceptor(Interceptors::MailAllowlistInterceptor)

  if Rails.env.production?
    ActionMailer::Base.register_interceptor(Interceptors::EmailThrottleInterceptor)
  end
end
