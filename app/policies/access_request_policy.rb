# frozen_string_literal: true

# Who may ask for access and who may decide.
#
# A member asks only for themselves. A manager of the request's group decides,
# or a superadmin. Nobody decides their own request.
class AccessRequestPolicy < ApplicationPolicy
  def create? = user.present? && record.user_id == user.id

  def approve? = decide?

  def deny? = decide?

  def decide?
    return false unless user && record.pending? && record.user_id != user.id

    user.superadmin? || record.group.managed_by?(user)
  end

  # The requests a user may decide: those for groups they manage, or every
  # request for a superadmin.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.superadmin?

      scope.where(group_id: user.managed_groups.select(:id))
    end

  end

end
