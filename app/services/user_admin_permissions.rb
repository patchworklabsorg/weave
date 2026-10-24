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
#
# Board membership is a role with its own grant rule (config/roles.yml): see
# RoleGrants and change_board?.
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

  # Board membership drives identity team governance: a board member approves
  # a new verifier, and the whole board approves a key holder change (see
  # IdentityGovernance). Only an owner changes it, so an admin can't put
  # themselves or a friend on the board, or empty it to approve alone. Each
  # change is logged and the board is told. Any owner changes it for any
  # person, other owners too (the any_owner rule in config/roles.yml): it
  # skips the peer rule of manage?. An owner may mark their own account:
  # that adds an approver, and nobody approves their own proposal.
  def change_board? = RoleGrants.allowed_now?(@actor, @target, "board", :grant)

  private

  def privileged? = @actor.superadmin? && !self_service? && outranks_target?

  def self_service? = @actor == @target

  def outranks_target? = rank(@actor) > rank(@target)

  def rank(user) = User.roles.fetch(user.role.to_s, 0)

end
