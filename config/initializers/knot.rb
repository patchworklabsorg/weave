# frozen_string_literal: true

# The Knot subscribes to the identifiers of each verification decision (see
# VerificationIdentifiers and KnotLinker). The block looks up KnotLinker at each
# call, so code reloading in development keeps working. An error in it rolls
# back the decision.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe(VerificationIdentifiers::EVENT) do |event|
    KnotLinker.decision_made(**event.payload.slice(:verification, :outcome, :identifiers))
  end
end
