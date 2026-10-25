# frozen_string_literal: true

# Removing a member and changing a member's role.
#
# A manager removes plain members of their group, and never another manager:
# managers can't push each other out. A superadmin removes anyone from a
# manual group. Rows that the system group sync owns are never removed by
# hand. Only a superadmin makes someone a manager or takes it away.
class Group::MembershipPolicy < ApplicationPolicy
  def destroy?
    return false unless user && record.manual? && record.group.manual?
    return true if user.superadmin?

    record.role_member? && record.group.managed_by?(user)
  end

  def update_role? = user.present? && user.superadmin? && record.manual? && record.group.manual?

end
