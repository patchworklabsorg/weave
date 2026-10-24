# frozen_string_literal: true

# The open values of identity team governance, from
# config/kyc/identity_governance.yml (see IdentityGovernance).
module IdentityGovernanceSettings
  PATH = Rails.root.join("config/kyc/identity_governance.yml")

  class << self
    def config = @config ||= Rails.application.config_for(PATH)

    def proposal_expiry = config.fetch(:proposal_expiry_days).days

    def verifier_minimum_age = config.fetch(:verifier_minimum_age)

    # p_ids that may join the identity team under verifier_minimum_age.
    def verifier_age_exceptions = Array(config[:verifier_age_exceptions]).map(&:to_s)

    # For specs that change a value.
    def reset! = @config = nil

  end
end
