# frozen_string_literal: true

# What an acting admin may see and change about a target user in the admin
# panel. Roles rank user < admin < superadmin < owner.
#
# Anyone in the admin panel may manage themselves and users strictly below
# them, and nobody else. Editing is not limited to role: changing a user's
# email is enough to take over their account, because magic links go to
# whatever address is on file. So a peer or superior must be out of reach
# entirely, not just their role.
#
# Role and password are privileged on top of that: only a superadmin or owner
# who outranks the target may change them, and never on their own account.
# Owners may grant any role (someone has to be able to appoint owners);
# everyone else only roles strictly below their own.
class UserAdminPermissions
  def initialize(actor, target)
    @actor = actor
    @target = target
  end

  def view? = @target.is_viewable?(@actor)

  def manage? = self_service? || outranks_target?

  # Role names the actor may give the target, in rank order. Empty when the
  # actor may not change the target's role at all.
  def assignable_roles
    return [] unless privileged?

    User.roles.keys.select { |role| @actor.owner? || User.roles[role] < rank(@actor) }
  end

  def assign_role?(role) = assignable_roles.include?(role.to_s)

  def change_password? = privileged?

  private

  def privileged? = @actor.superadmin? && !self_service? && outranks_target?

  def self_service? = @actor == @target

  def outranks_target? = rank(@actor) > rank(@target)

  def rank(user) = User.roles.fetch(user.role.to_s, 0)

end
