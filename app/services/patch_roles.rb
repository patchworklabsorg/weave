# frozen_string_literal: true

# A person's roles for each patch, as apps see them in the `patches` claim and
# in the directory API (see docs/OAUTH.md "Patch claims").
#
# This is the contract with Quilt and the other patch apps. Keep the shape:
# a JSON object that maps a patch slug to the sorted, unique role keys the
# person holds for that patch, for example
#
#   {"europa": ["reviewer"], "ganymede": ["lead", "quilt:viewer", "reviewer"]}
#
# - "lead" comes from an active patch_lead role (config/roles.yml, granted
#   through identity governance) scoped to the slug.
# - Every other key is a PatchRole that a superadmin defined for the patch,
#   held directly or through an active group membership (the same rule as
#   AppAccess.role_keys).
# - The keys are patch slugs, sorted. Only patches that exist are listed.
# - An empty object ({}) when the person holds no patch role.
module PatchRoles
  # The claim key of the patch_lead governance role. PatchRole refuses it as
  # a key (PatchRole::RESERVED_KEYS).
  LEAD = "lead"

  # The claim value for one user.
  def self.for(user)
    return {} if user.nil?

    keys = Hash.new { |hash, slug| hash[slug] = [] }

    lead_slugs = user.role_scopes("patch_lead")
    Patch.where(slug: lead_slugs).pluck(:slug).each { |slug| keys[slug] << LEAD } if lead_slugs.any?

    PatchRole.held_by(user).joins(:patch).pluck("patches.slug", "patch_roles.key").each { |slug, key| keys[slug] << key }

    keys.sort.to_h { |slug, role_keys| [slug, role_keys.uniq.sort] }
  end

end
