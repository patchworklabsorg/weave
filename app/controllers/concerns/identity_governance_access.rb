# frozen_string_literal: true

# Access to the identity team governance pages (see IdentityGovernance):
# owners, board members and identity team leads. The admin role is not
# needed. Each action checks its own rule in IdentityGovernance.
module IdentityGovernanceAccess
  extend ActiveSupport::Concern

  included do
    skip_before_action :require_identity_team
    before_action :require_governance_access
  end

  private

  def require_governance_access
    return if IdentityGovernance.can_view?(current_user)

    redirect_to root_path, alert: "Only owners, board members and identity team leads can open this page."
  end

  # A person by Weave ID (p_id) or email address.
  def find_person(value)
    value = value.to_s.strip
    return nil if value.blank?

    User.find_by(p_id: value) || User.find_by(email: value.downcase)
  end

end
