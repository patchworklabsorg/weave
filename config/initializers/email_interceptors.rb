# frozen_string_literal: true

# Register email interceptors
if Rails.env.production?
  ActionMailer::Base.register_interceptor(Interceptors::EmailThrottleInterceptor)
end
