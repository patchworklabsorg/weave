# frozen_string_literal: true

# Register email interceptors
Rails.application.config.to_prepare do
  if Rails.env.production?
    ActionMailer::Base.register_interceptor(Interceptors::EmailThrottleInterceptor)
  end
end
