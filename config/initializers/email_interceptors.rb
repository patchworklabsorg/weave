# frozen_string_literal: true

# Register email interceptors
Rails.application.config.to_prepare do
  # First, so recipients it drops never count against the daily throttle. It is
  # a no-op unless MAIL_ALLOWLIST or WEAVE_ENV=staging is set.
  ActionMailer::Base.register_interceptor(Interceptors::MailAllowlistInterceptor)

  if Rails.env.production?
    ActionMailer::Base.register_interceptor(Interceptors::EmailThrottleInterceptor)
  end
end
