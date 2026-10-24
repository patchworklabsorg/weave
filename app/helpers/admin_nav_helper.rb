# frozen_string_literal: true

# The sidebar of the admin and identity layout (shared/_sidebar) and the
# admin pages of the ⌘K command bar (shared/_command_bar): four headed
# groups. Each person sees only the groups and links they can use. A
# verifier without the admin role sees only Identity.
#
# A link is active when the current controller is one of its controllers (a
# name that ends in "*" matches as a prefix), or when the request path starts
# with the link's path (the mounted engines: jobs, Flipper, Blazer, the
# console audits).
module AdminNavHelper
  NavLink = Data.define(:label, :path, :icon, :keywords, :controllers, :prefix) do
    def active?(controller_path, request_path)
      controllers.any? { |name| name.end_with?("*") ? controller_path.start_with?(name.chomp("*")) : name == controller_path } ||
        (prefix && (request_path == path || request_path.start_with?("#{path}/")))
    end
  end

  NavGroup = Data.define(:title, :links)

  # The groups the user can see, each with at least one link.
  def admin_nav_groups(user = current_user)
    return [] if user.nil?

    admin = user.admin?
    groups = [
      NavGroup.new("Identity", [
        (admin_nav_entry("Verification", identity_verifications_path, :id_card, "identity id check call review",
                         %w[verifications break_glass_records break_glass_notices], :identity) if user.identity_team),
        (admin_nav_entry("Key custody", identity_key_custody_path, :key_square, "hardware keys yubikey ceremony break-glass",
                         %w[key_custody key_ceremonies hardware_keys key_sets], :identity) if KeyCustody.can_view?(user)),
        (admin_nav_entry("Governance", identity_governance_path, :landmark, "identity team board proposals nda",
                         %w[governance governance_proposals ndas team_removals], :identity) if IdentityGovernance.can_view?(user)),
        (admin_nav_entry("Knot", admin_knots_path, :link, "knot hash program grants",
                         %w[knots knot_change_requests], :admin) if admin && knot_nav?(user))
      ]),
      NavGroup.new("People", [
        (admin_nav_entry("Users", admin_users_path, :users, "admin people members", %w[users user_*], :admin) if admin),
        (admin_nav_entry("Groups", admin_groups_path, :users_round, "admin teams", %w[groups group_memberships], :admin) if admin),
        (admin_nav_entry("Consents", admin_guardian_consents_path, :shield_check, "admin guardian minors review queue",
                         %w[guardian_consents], :admin) if admin)
      ]),
      NavGroup.new("Data", [
        (admin_nav_entry("Deletion", admin_deletion_requests_path, :trash_2, "deletion requests takeout retention",
                         %w[deletion_requests delete_time_aggregates], :admin) if admin && user.identity_team),
        (admin_nav_entry("Demographics", admin_demographics_path, :chart_pie, "demographics vault report",
                         %w[demographics], :admin) if admin),
        (admin_nav_entry("Funder reports", admin_funder_reports_path, :file_chart_column, "funder report aggregates",
                         %w[funder_reports], :admin) if admin)
      ]),
      NavGroup.new("System", admin ? system_links : [])
    ]
    groups.map { |group| group.with(links: group.links.compact) }.reject { |group| group.links.empty? }
  end

  def admin_nav_link_active?(link) = link.active?(controller_path, request.path)

  private

  def system_links
    [
      NavLink.new("Dashboard", admin_root_path, :layout_dashboard, "admin home", %w[admin/dashboard], false),
      admin_nav_entry("OAuth apps", admin_oauth_applications_path, :app_window, "admin applications clients",
                      %w[oauth_applications oauth_application_roles oauth_application_role_assignments oauth_application_access_grants
                         services service_keys service_webhooks], :admin),
      NavLink.new("Jobs", "/admin/jobs", :activity, "admin mission control queue", [], true),
      NavLink.new("Feature flags", "/admin/flipper", :flag, "admin flipper", [], true),
      NavLink.new("Blazer", "/admin/blazer", :database, "admin sql queries reports", [], true),
      NavLink.new("Console audits", "/admin/console", :terminal, "admin audits1984", [], true),
      admin_nav_entry("Console sign-in", admin_console_access_path, :key_round, "admin production console dbconsole code",
                      %w[console_access], :admin)
    ]
  end

  def admin_nav_entry(label, path, icon, keywords, controllers, namespace)
    NavLink.new(label, path, icon, keywords, controllers.map { |name| "#{namespace}/#{name}" }, false)
  end

  # The Knot pages: the identity team, the board and the program patch leads.
  def knot_nav?(user)
    user.identity_team || user.is_board || KnotSettings.program_keys.any? { |program| KnotGrants.patch_lead?(user, program) }
  end
end
