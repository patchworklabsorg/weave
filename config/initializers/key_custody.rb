# frozen_string_literal: true

# A change of the key holder set forces a master-key rotation: the current
# key set is marked compromised (see KeyCustody.key_holders_changed). The
# block looks up KeyCustody at each call, so code reloading keeps working.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe(IdentityGovernance::KEY_HOLDERS_CHANGED) do |event|
    KeyCustody.key_holders_changed(**event.payload.slice(:user, :change, :actor))
  end
end
