# frozen_string_literal: true

# Marks pending identity team proposals past their expiry as expired, with a
# governance event (see IdentityGovernance.expire_due!). An approval also
# refuses an expired proposal, so this job keeps the page and the log
# accurate. It does not grant or block anything by itself.
class ExpireIdentityGovernanceProposalsJob < ApplicationJob
  queue_as :low

  def perform
    PaperTrail.request(whodunnit: "ExpireIdentityGovernanceProposalsJob") do
      IdentityGovernance.expire_due!
    end
  end

end
