# frozen_string_literal: true

require Rails.root.join("lib/feature_flags").to_s

Rails.application.configure do
  # Flipper memoizes and preloads every flag for each request by default, which
  # suits the small number of flags here.

  # Flipper calls FeatureFlags::STRICT for a flag that is not in the store. It
  # raises in development and test for a flag that is not in FeatureFlags::FLAGS.
  config.flipper.strict = FeatureFlags::STRICT
end

Flipper.configure do |config|
  config.use FeatureFlags::UserActorAdapter
end

Flipper::UI.configure do |config|
  config.descriptions_source = ->(keys) { FeatureFlags::FLAGS.transform_keys(&:to_s).slice(*keys) }
  config.show_feature_description_in_list = true
  config.actor_names_source = ->(actor_ids) { FeatureFlags::ActorNames.call(actor_ids) }
  config.add_actor_placeholder = "an email, a #{Weave.p_id_prefix} id, a usr_ id, or a Slack id"
  # The version check fetches www.flippercloud.io from the browser, which the
  # Content Security Policy does not allow.
  config.version_check_enabled = false
end

FeatureFlags::Groups.register_all

# Create every flag in FeatureFlags::FLAGS, so the Flipper UI shows the full list.
#
# This also runs on the boot at the start of `rails db:migrate`. On a database
# that is not migrated yet (CI, first-time setup) flipper_features does not
# exist, and Flipper.add raises. The flags are created on the next boot.
Rails.application.config.after_initialize do
  FeatureFlags.add_all if ActiveRecord::Base.connection.data_source_exists?("flipper_features")
rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
  # The database is not reachable or not created yet.
end
