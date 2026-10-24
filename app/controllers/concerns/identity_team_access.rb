# frozen_string_literal: true

# Admin pages for the identity team (see Verification). The identity team is
# a flag on the user (User#identity_team), mirrored into the "identity-team"
# system group. The pages live in the admin panel, so a member of the team
# also needs the admin role to reach them.
module IdentityTeamAccess
  extend ActiveSupport::Concern

  included do
    before_action :require_identity_team
  end

  private

  def require_identity_team
    return if current_user&.identity_team

    redirect_to admin_root_path, alert: "Only the identity team can open this page."
  end

end
