# frozen_string_literal: true

# Who may use which OAuth app.
#
# An app's access_policy is "everyone" (any user who can sign in) or
# "restricted" (only users with a matching ApplicationAccessGrant, directly or
# through an unexpired group membership). Any value other than "everyone"
# counts as restricted, so a bad value fails closed.
#
# There is no admin bypass: an admin needs a grant like anyone else.
#
# Every place that hands out or honors a user's token asks this module:
# the authorize endpoint, the token endpoint (code exchange and refresh),
# introspection, and userinfo. Checking at consent alone is not enough,
# because a refresh token would keep working after access is removed.
module AppAccess
  Decision = Data.define(:permitted, :reason, :groups) do
    alias_method :permitted?, :permitted

    def to_s
      case reason
      when :open then "Open to everyone"
      when :direct then "Direct grant"
      when :group then "Member of #{groups.map(&:name).to_sentence}"
      when :no_user then "No user"
      else "No grant for this user or their groups"
      end
    end
  end

  class << self
    def permitted?(user, application) = explain(user, application).permitted?

    def explain(user, application)
      return decision(true, :open) unless restricted?(application)
      return decision(false, :no_user) if user.nil?

      grants = ApplicationAccessGrant.for_application(application)
      return decision(true, :direct) if grants.exists?(grantee: user)

      groups = user.groups.where(id: grants.where(grantee_type: "Group").select(:grantee_id)).order(:name).to_a
      return decision(true, :group, groups) if groups.any?

      decision(false, :no_grant)
    end

    def restricted?(application) = application.access_policy != "everyone"

    # Whether a token may still be used: its user can sign in and may use the
    # app it was issued to. A token with no user (client_credentials) involves
    # no user access, so it passes.
    def token_usable?(token)
      return true if token.resource_owner_id.nil?

      user = User.find_by(id: token.resource_owner_id)
      return false unless user&.can_authenticate?

      application = token.application
      application.nil? || permitted?(user, application)
    end

    private

    def decision(permitted, reason, groups = []) = Decision.new(permitted:, reason:, groups:)

  end
end
