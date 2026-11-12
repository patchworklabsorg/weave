# frozen_string_literal: true

# Copies the roles of one OAuth app into a patch, as patch roles with an app
# prefix (see PatchRole and docs/OAUTH.md "Moving app roles to a patch").
# For example, Krater's app roles `reviewer` and `admin` become the Ganymede
# patch roles `krater:reviewer` and `krater:admin`.
#
# - Each app role becomes the patch role "<prefix>:<key>", with the same name
#   and description. An existing patch role with that key is kept as it is.
# - Each assignment of the app role becomes a patch role assignment: a user,
#   or a manual group. A system group is skipped: it can't hold a patch role
#   (see PatchRoleAssignment).
# - group_map gives the patch role of an app role key to a group too, even
#   with no app role assignment for it. Manual groups only, the same rule.
# - The app roles and their assignments are never changed: the app reads them
#   until it reads the `patches` claim.
#
# A dry run (the default) writes nothing and returns the plan. apply: true
# writes the plan in one transaction, with the actor as created_by and as the
# PaperTrail whodunnit. A second run creates nothing: each item is reported
# as already present. Only a superadmin can be the actor.
module PatchRoleImport
  class Error < StandardError; end

  PREFIX_FORMAT = /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/

  # status: :create, :present or :skip.
  Step = Data.define(:status, :text)

  Result = Data.define(:steps, :groups, :applied) do
    def created = steps.count { |step| step.status == :create }

    def lines
      header = applied ? "Applied. Weave wrote the items marked create." : "Dry run. Nothing was written. Run again with APPLY=1 to write it."
      list = steps.map { |step| "#{step.status.to_s.ljust(7)} #{step.text}" }
      warning = if groups.any?
                  ["Warning: these groups hold a patch role. Only a superadmin can add members to them now: " \
                   "#{groups.map(&:slug).sort.join(', ')}."]
                else
                  []
                end
      [header, *list, *warning]
    end
  end

  class << self
    def call(application:, patch:, prefix:, actor:, group_map: {}, apply: false)
      check!(application:, patch:, prefix:, actor:)
      app_roles = ApplicationRole.for_application(application).includes(assignments: :assignee).order(:key).to_a
      extra = map_groups(group_map, app_roles)

      plan = Plan.new(patch:, prefix:, actor:, apply:)
      work = -> { app_roles.each { |app_role| plan.add_role(app_role, extra.fetch(app_role.key, [])) } }
      if apply
        PaperTrail.request(whodunnit: actor.id.to_s) { ApplicationRecord.transaction { work.call } }
      else
        work.call
      end
      Result.new(steps: plan.steps, groups: plan.groups.uniq, applied: apply)
    end

    private

    def check!(application:, patch:, prefix:, actor:)
      raise Error, "Unknown app." if application.nil?
      raise Error, "Unknown patch." if patch.nil?
      raise Error, "The prefix must be lowercase letters and digits, for example krater." unless prefix.to_s.match?(PREFIX_FORMAT)
      raise Error, "The actor must be a superadmin." unless actor&.superadmin?
    end

    # { "reviewer" => [group, ...] } from { "krater-reviewers" => "reviewer" }.
    def map_groups(group_map, app_roles)
      keys = app_roles.map(&:key)
      group_map.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(slug, key), result|
        group = Group.find_by(slug:)
        raise Error, "Unknown group #{slug}." if group.nil?
        raise Error, "The app has no role #{key} (GROUP_MAP #{slug}:#{key})." unless keys.include?(key)

        result[key] << group
      end
    end

  end

  # Builds the steps, and writes them when apply is true.
  class Plan
    attr_reader :steps, :groups

    def initialize(patch:, prefix:, actor:, apply:)
      @patch = patch
      @prefix = prefix
      @actor = actor
      @apply = apply
      @steps = []
      @groups = []
    end

    def add_role(app_role, extra_groups)
      key = "#{@prefix}:#{app_role.key}"
      role = @patch.roles.find_by(key:)
      if role
        @steps << Step.new(status: :present, text: "role #{key} on #{@patch.slug}")
      else
        @steps << Step.new(status: :create, text: "role #{key} on #{@patch.slug} (#{app_role.name})")
        if @apply
          role = @patch.roles.create!(key:, name: app_role.name, description: app_role.description, created_by: @actor)
        end
      end

      assignees = (app_role.assignments.map(&:assignee).compact + extra_groups).uniq
      assignees.each { |assignee| add_assignment(role, key, assignee) }
    end

    private

    def add_assignment(role, key, assignee)
      label = assignee.is_a?(Group) ? "group #{assignee.slug}" : "user #{assignee.email}"
      if assignee.is_a?(Group) && !assignee.manual?
        @steps << Step.new(status: :skip, text: "#{key} for #{label}: a system group can't hold a patch role")
        return
      end

      @groups << assignee if assignee.is_a?(Group)
      if role&.persisted? && role.assignments.exists?(assignee:)
        @steps << Step.new(status: :present, text: "#{key} for #{label}")
      else
        @steps << Step.new(status: :create, text: "#{key} for #{label}")
        PatchRoleAssignment.create!(role:, assignee:, created_by: @actor) if @apply
      end
    end

  end

end
