# frozen_string_literal: true

# Who may manage a group outside the admin panel (GroupsController). A manager
# of a manual group, or a superadmin, may see the group, add members, and
# decide its access requests. System groups follow user attributes, so nobody
# manages them by hand. See Group::MembershipPolicy for removing members.
class GroupPolicy < ApplicationPolicy
  def index? = user.present?

  def show? = manage?

  def manage?
    return false unless user && record.manual?

    user.superadmin? || record.managed_by?(user)
  end

  # A sponsored project group waives the code of conduct or the Slack for its
  # members, so only a superadmin adds people to it (see Group).
  def add_member?
    return false unless manage?

    user.superadmin? || !(record.waives_code_of_conduct || record.waives_slack)
  end

  # The groups listed on /groups: the ones the user manages.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      scope.where(id: user.managed_groups.select(:id))
    end

  end

end
