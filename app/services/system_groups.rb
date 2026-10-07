# frozen_string_literal: true

# Built-in groups that follow user attributes.
#
# Most access rules follow facts Weave already holds ("all staff", "all board
# members"). Each such fact gets a system group, and Weave keeps its members in
# sync. Every access check can then be the same question: is the user in group
# X? There is no rule engine to evaluate.
#
# Memberships made here have `source: system`. A sync adds and removes system
# rows only, so it never touches a membership that was added by hand.
module SystemGroups
  Definition = Data.define(:slug, :name, :description, :attributes, :rule)

  DEFINITIONS = [
    Definition.new(
      slug: "staff", name: "Staff", description: "Users marked as staff.",
      attributes: %w[is_staff], rule: ->(user) { user.is_staff }
    ),
    Definition.new(
      slug: "board", name: "Board", description: "Users marked as board members.",
      attributes: %w[is_board], rule: ->(user) { user.is_board }
    ),
    Definition.new(
      slug: "contractors", name: "Contractors", description: "Users marked as contractors.",
      attributes: %w[is_contractor], rule: ->(user) { user.is_contractor }
    ),
    Definition.new(
      slug: "admins", name: "Admins", description: "Users with the admin, superadmin or owner role.",
      attributes: %w[role], rule: ->(user) { user.admin? }
    ),
    Definition.new(
      slug: "slack-members", name: "Slack Members", description: "Full members of the Patchwork Labs Slack.",
      attributes: %w[slack_membership], rule: ->(user) { user.slack_member? }
    )
  ].freeze

  SLUGS = DEFINITIONS.map(&:slug).freeze

  # The user attributes that can change a system group membership.
  ATTRIBUTES = DEFINITIONS.flat_map(&:attributes).uniq.freeze

  class << self
    # Creates any system group that does not exist yet, and returns the groups
    # by slug. A manual group can't take a reserved slug (see Group), so a
    # live group with one of these slugs is always the system group.
    def ensure_groups!
      DEFINITIONS.to_h do |definition|
        group = Group.find_or_create_by!(slug: definition.slug) do |new_group|
          new_group.name = definition.name
          new_group.description = definition.description
          new_group.kind = "system"
        end
        [definition.slug, group]
      end
    end

    # Brings one user's system memberships in line with their attributes.
    def sync(user, groups: ensure_groups!)
      existing = user.group_memberships.where(group: groups.values).index_by(&:group_id)

      DEFINITIONS.each do |definition|
        group = groups.fetch(definition.slug)
        membership = existing[group.id]

        if definition.rule.call(user)
          group.memberships.create!(user: user, source: "system") if membership.nil?
        elsif membership&.system?
          membership.destroy!
        end
      end
    end

    # Syncs every user. For the first fill after deploy and for drift repair.
    def sync_all
      groups = ensure_groups!
      User.find_each { |user| sync(user, groups: groups) }
    end

  end
end
