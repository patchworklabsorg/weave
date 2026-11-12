# frozen_string_literal: true

# Copies the roles of one OAuth app into a patch, as patch roles with an app
# prefix (see PatchRole and docs/OAUTH.md "Moving app roles to a patch").
# For example, Krater's app roles `reviewer` and `admin` become the Ganymede
# patch roles `krater:reviewer` and `krater:admin`.
#
# - The app must belong to the patch (a superadmin links it first).
# - Each app role becomes the patch role "<prefix>:<key>", with the same name
#   and description. A patch role with that key that has another name or
#   description is a conflict: APPLY refuses unless merge is true, and then
#   keeps the patch role as it is.
# - Each assignment of the app role becomes a patch role assignment: a user,
#   or a manual group. A system group is skipped: it can't hold a patch role
#   (see PatchRoleAssignment).
# - group_map gives the patch role of an app role key to a group too, even
#   with no app role assignment for it ("grant", with the group's active
#   member count). Manual groups only, the same rule.
# - An assignment that an admin removed before (a PaperTrail destroy version)
#   is skipped as "previously removed", unless restore is true.
# - The app roles and their assignments are never changed: the app reads them
#   until it reads the `patches` claim.
#
# A dry run (the default) builds every record and checks it, and writes
# nothing. apply: true refuses when an item is invalid or a conflict (without
# merge), and otherwise writes the plan in one transaction, with the actor as
# created_by and as the PaperTrail whodunnit. A second run creates nothing.
# Only a superadmin can be the actor.
module PatchRoleImport
  class Error < StandardError; end

  PREFIX_FORMAT = /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/

  # status: :create, :grant, :present, :conflict, :skip, :removed or :invalid.
  # record: the unsaved record that APPLY saves, for :create and :grant.
  Step = Data.define(:status, :text, :record) do
    def initialize(status:, text:, record: nil) = super

    def label = status == :removed ? "previously removed" : status.to_s
  end

  WRITES = %i[create grant].freeze

  Result = Data.define(:steps, :groups, :applied, :header) do
    def created = steps.count { |step| WRITES.include?(step.status) }

    def lines
      mode = applied ? "Applied. Weave wrote the items marked create and grant." : "Dry run. Nothing was written. Run again with APPLY=1 to write it."
      list = steps.map { |step| "#{step.label.ljust(8)} #{step.text}" }
      warning = if groups.any?
                  ["Warning: these groups hold a patch role. Only a superadmin can add members to them now: " \
                   "#{groups.map(&:slug).sort.join(', ')}."]
                else
                  []
                end
      [header, mode, *list, *warning]
    end
  end

  class << self
    def call(application:, patch:, prefix:, actor:, group_map: {}, apply: false, merge: false, restore: false)
      check!(application:, patch:, prefix:, actor:)
      app_roles = ApplicationRole.for_application(application).includes(assignments: :assignee).order(:key).to_a
      extra = map_groups(group_map, app_roles)

      plan = Plan.new(patch:, prefix:, actor:, restore:)
      app_roles.each { |app_role| plan.add_role(app_role, extra.fetch(app_role.key, [])) }
      header = "App: #{application.name} (client id #{application.uid}). Patch: #{patch.name} (#{patch.slug})."
      result = Result.new(steps: plan.steps, groups: plan.groups.uniq, applied: apply, header:)
      return result unless apply

      refuse_apply!(result.steps, merge:)
      PaperTrail.request(whodunnit: actor.id.to_s) do
        ApplicationRecord.transaction { result.steps.each { |step| step.record&.save! } }
      end
      result
    end

    private

    def check!(application:, patch:, prefix:, actor:)
      raise Error, "Unknown app." if application.nil?
      raise Error, "Unknown patch." if patch.nil?
      raise Error, "The prefix must be lowercase letters and digits, for example krater." unless prefix.to_s.match?(PREFIX_FORMAT)
      raise Error, "The actor must be a superadmin." unless actor&.superadmin?
      return if application.patch_id == patch.id

      raise Error, "#{application.name} does not belong to #{patch.slug}. A superadmin links the app to the patch first (the Patch field on the app's edit page)."
    end

    def refuse_apply!(steps, merge:)
      invalid = steps.select { |step| step.status == :invalid }
      raise Error, "Nothing was written. Fix the invalid items first: #{invalid.map(&:text).join('; ')}" if invalid.any?

      conflicts = steps.select { |step| step.status == :conflict }
      return if conflicts.empty? || merge

      raise Error, "Nothing was written. A patch role with the same key differs: #{conflicts.map(&:text).join('; ')}. " \
                   "Run with MERGE=1 to keep the patch roles as they are and add the assignments."
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

  # Builds the steps and the unsaved records. Writes nothing.
  class Plan
    attr_reader :steps, :groups

    def initialize(patch:, prefix:, actor:, restore:)
      @patch = patch
      @prefix = prefix
      @actor = actor
      @restore = restore
      @steps = []
      @groups = []
    end

    def add_role(app_role, extra_groups)
      key = "#{@prefix}:#{app_role.key}"
      role = role_step(app_role, key)
      return if role.nil?

      assigned = app_role.assignments.map(&:assignee).compact.uniq
      assigned.each { |assignee| add_assignment(role, key, assignee, granted: false) }
      (extra_groups.uniq - assigned).each { |group| add_assignment(role, key, group, granted: true) }
    end

    private

    # The patch role (saved or unsaved), or nil when it is invalid.
    def role_step(app_role, key)
      role = @patch.roles.find_by(key:)
      if role.nil?
        role = PatchRole.new(patch: @patch, key:, name: app_role.name, description: app_role.description, created_by: @actor)
        return invalid("role #{key}", role) unless role.valid?

        @steps << Step.new(status: :create, text: "role #{key} on #{@patch.slug} (#{app_role.name})", record: role)
      elsif role.name != app_role.name || role.description.presence != app_role.description.presence
        @steps << Step.new(status: :conflict,
                           text: "role #{key} on #{@patch.slug} is named #{role.name.inspect} with description " \
                                 "#{role.description.inspect}, the app role #{app_role.name.inspect} with #{app_role.description.inspect}")
      else
        @steps << Step.new(status: :present, text: "role #{key} on #{@patch.slug}")
      end
      role
    end

    def add_assignment(role, key, assignee, granted:)
      label = assignee.is_a?(Group) ? "group #{assignee.slug}" : "user #{assignee.email}"
      text = "#{key} for #{label}"
      text += " (#{assignee.active_memberships.count} active members)" if granted

      if assignee.is_a?(Group) && !assignee.manual?
        @steps << Step.new(status: :skip, text: "#{text}: a system group can't hold a patch role")
      elsif role.persisted? && role.assignments.exists?(assignee:)
        @groups << assignee if assignee.is_a?(Group)
        @steps << Step.new(status: :present, text:)
      elsif role.persisted? && removed_before?(role, assignee) && !@restore
        @steps << Step.new(status: :removed, text: "#{text}: an admin removed it, run with RESTORE=1 to give it back")
      else
        add_new_assignment(role, assignee, text, granted:)
      end
    end

    def add_new_assignment(role, assignee, text, granted:)
      assignment = PatchRoleAssignment.new(role:, assignee:, created_by: @actor)
      return invalid(text, assignment) unless assignment.valid?

      @groups << assignee if assignee.is_a?(Group)
      @steps << Step.new(status: granted ? :grant : :create, text:, record: assignment)
    end

    def removed_before?(role, assignee)
      PaperTrail::Version.where(item_type: "PatchRoleAssignment", event: "destroy")
                         .where_object(role_id: role.id, assignee_type: assignee.class.name, assignee_id: assignee.id)
                         .exists?
    end

    def invalid(text, record)
      @steps << Step.new(status: :invalid, text: "#{text}: #{record.errors.full_messages.to_sentence}")
      nil
    end

  end

end
