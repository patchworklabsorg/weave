# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  include Bullet::ActiveJob if Rails.env.development?
  # Use Solid Queue everywhere except test, where the environment configures
  # the :test adapter (the Solid Queue tables do not exist in the test DB).
  self.queue_adapter = :solid_queue unless Rails.env.test?

  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

end
