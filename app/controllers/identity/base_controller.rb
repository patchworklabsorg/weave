# frozen_string_literal: true

# The identity area (/identity): the verification pages for the identity team
# and the governance page (see IdentityGovernance). It is not part of /admin.
# A verifier does not need the admin role, and the admin role alone does not
# open these pages: each page has its own access rule.
#
# An admin who impersonates a member can't use these pages, so nobody acts as
# a verifier in another person's name.
class Identity::BaseController < ApplicationController
  before_action :refuse_impersonation
  before_action :require_identity_team

  layout "admin"

  private

  def refuse_impersonation
    return unless impersonating?

    redirect_to root_path, alert: "Stop impersonating before you open the identity pages."
  end

  def require_identity_team
    return if current_user&.identity_team

    redirect_to root_path, alert: "Only the identity team can open this page."
  end

end
