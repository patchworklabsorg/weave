# frozen_string_literal: true

# Who may use which OAuth app.
#
# An app's access_policy is "everyone" (any user who can sign in) or
# "restricted" (only users with a matching ApplicationAccessGrant or a role in
# the app, directly or through an unexpired group membership). Any value other than "everyone"
# counts as restricted, so a bad value fails closed.
#
# There is no admin bypass: an admin needs a grant like anyone else.
#
# When the :require_code_of_conduct flag is on, a user who has not accepted
# the code of conduct may use no app at all, open or restricted. The flag is
# read only when the feature exists, so a missing flag means "off" and never
# trips Flipper's strict mode in production.
#
# Every place that hands out or honors a user's token asks this module:
# the authorize endpoint, the token endpoint (code exchange and refresh),
# introspection, and userinfo. Checking at consent alone is not enough,
# because a refresh token would keep working after access is removed.
module AppAccess
  CODE_OF_CONDUCT_FLAG = :require_code_of_conduct

  Decision = Data.define(:permitted, :reason, :groups, :roles) do
    alias_method :permitted?, :permitted

    def to_s
      case reason
      when :open then "Open to everyone"
      when :direct then "Direct grant"
      when :group then "Member of #{groups.map(&:name).to_sentence}"
      when :role then "Holds the #{roles.map(&:name).to_sentence} role"
      when :no_user then "No user"
      when :code_of_conduct then "Has not accepted the Code of Conduct"
      else "No grant for this user or their groups"
      end
    end
  end

  class << self
    def permitted?(user, application) = explain(user, application).permitted?

    def explain(user, application)
      return decision(false, :code_of_conduct) if code_of_conduct_missing?(user)
      return decision(true, :open) unless restricted?(application)
      return decision(false, :no_user) if user.nil?

      grants = ApplicationAccessGrant.for_application(application)
      return decision(true, :direct) if grants.exists?(grantee: user)

      groups = user.groups.where(id: grants.where(grantee_type: "Group").select(:grantee_id)).order(:name).to_a
      return decision(true, :group, groups:) if groups.any?

      roles = ApplicationRole.for_application(application).held_by(user).order(:name).to_a
      return decision(true, :role, roles:) if roles.any?

      decision(false, :no_grant)
    end

    def restricted?(application) = application.access_policy != "everyone"

    def code_of_conduct_required? = Flipper.exist?(CODE_OF_CONDUCT_FLAG) && Flipper.enabled?(CODE_OF_CONDUCT_FLAG)

    def code_of_conduct_missing?(user) = user.present? && user.slack_coc_accepted_at.nil? && code_of_conduct_required?

    # Groups linked to an app by an access grant or a role assignment. These
    # are the only groups the app may see (the `groups` claim, the directory).
    def linked_groups(application)
      granted = ApplicationAccessGrant.for_application(application).where(grantee_type: "Group").select(:grantee_id)
      assigned = ApplicationRoleAssignment.for_application(application).where(assignee_type: "Group").select(:assignee_id)
      Group.where(id: granted).or(Group.where(id: assigned))
    end

    # Slugs of the user's groups that are linked to the app, sorted.
    def group_slugs(user, application)
      user.groups.where(id: linked_groups(application).select(:id)).order(:slug).pluck(:slug)
    end

    # Keys of the app's roles that the user holds, sorted.
    def role_keys(user, application)
      ApplicationRole.for_application(application).held_by(user).order(:key).pluck(:key)
    end

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

    def decision(permitted, reason, groups: [], roles: []) = Decision.new(permitted:, reason:, groups:, roles:)

  end
end
