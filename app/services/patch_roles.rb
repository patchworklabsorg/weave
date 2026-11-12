# frozen_string_literal: true

# A person's roles for each patch, as apps see them in the `patches` claim and
# in the directory API (see docs/OAUTH.md "Patch claims").
#
# This is the contract with Quilt and the other patch apps. Keep the shape:
# a JSON object that maps a patch slug to the sorted list of short role names
# the person actively holds for that patch, for example
#
#   {"ganymede": ["lead"], "europa": ["viewer"]}
#
# - The keys are patch slugs, sorted. Only patches that exist are listed.
# - A revoked role is left out.
# - An empty object ({}) when the person holds no patch role.
module PatchRoles
  # The role key in config/roles.yml => its short name in the claim. Add a
  # new per-patch role here, or apps never see it.
  NAMES = {
    "patch_lead"   => "lead",
    "patch_viewer" => "viewer"
  }.freeze

  # The claim value for one user.
  def self.for(user)
    return {} if user.nil?

    held = user.active_user_roles.select { |assignment| NAMES.key?(assignment.role.key) && assignment.scope.present? }
    return {} if held.empty?

    existing = Patch.where(slug: held.map(&:scope).uniq).pluck(:slug).to_set
    held.select { |assignment| existing.include?(assignment.scope) }
        .group_by(&:scope)
        .sort_by(&:first)
        .to_h { |slug, assignments| [slug, assignments.map { |assignment| NAMES.fetch(assignment.role.key) }.uniq.sort] }
  end

end
