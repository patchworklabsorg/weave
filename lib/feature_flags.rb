# frozen_string_literal: true

# The feature flags that Weave checks, and the Flipper setup that goes with them.
# config/initializers/flipper.rb requires this file by hand, so Zeitwerk ignores
# it (see config/application.rb): an initializer cannot use a reloadable constant.
module FeatureFlags
  class UnknownFlag < StandardError; end

  # Every flag that the app checks, with a description for the Flipper UI. Add a
  # flag here before you call Flipper.enabled? for it. The initializer creates
  # each flag at boot, disabled, so the UI shows it before anyone turns it on.
  FLAGS = {}.freeze

  # The strict handler for Flipper. Flipper calls it when code checks a flag that
  # is not in the store yet. A flag that is not in FLAGS raises in development and
  # test, so a spec catches it, and only logs in production, so a typo does not
  # break a request.
  STRICT = ->(feature) { check_registered!(feature.key) }

  def self.registered?(key)
    FLAGS.key?(key.to_sym)
  end

  def self.check_registered!(key)
    return if registered?(key)

    message = "#{key.inspect} is not in FeatureFlags::FLAGS. Add it there first."
    raise UnknownFlag, message unless Rails.env.production?

    Rails.logger.warn("[flipper] #{message}")
  end

  # Creates every flag in FLAGS in the store. Flipper.add never changes a flag
  # that exists, so this is safe on every boot.
  def self.add_all
    FLAGS.each_key { |key| Flipper.add(key) }
  end
end

require_relative "feature_flags/user_lookup"
require_relative "feature_flags/groups"
require_relative "feature_flags/user_actor_adapter"
require_relative "feature_flags/actor_names"
