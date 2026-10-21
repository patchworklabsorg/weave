# frozen_string_literal: true

# The Doorkeeper application that Google Workspace uses as its OIDC client
# (the "third-party SSO profile" in the Google Admin console).
#
# Who has Google sign-in: the members of the `google-workspace` group. The
# app is restricted (see AppAccess) and the group is its only access grant,
# so a user outside the group gets the "You don't have access" page and
# Google gets no code. A sponsored project's people can be in the group too;
# their project group decides whether they need the code of conduct.
#
# Google matches the `email` claim against the person's primary Google
# address, so the app has email_domains, and the claim is the user's
# confirmed address on one of them (see AppAccess.email_for).
#
# Made by `bin/rails google_workspace:setup`, never by hard-coded secrets.
# Doorkeeper generates the client id and secret; an admin reads them in the
# admin panel and enters them in Google.
module GoogleWorkspaceApp
  NAME = "Google Workspace"
  GROUP_SLUG = "google-workspace"
  SCOPES = "openid email profile"
  DEFAULT_EMAIL_DOMAINS = %w[patchworklabs.org hackboston.dev hackathon.help].freeze

  Result = Data.define(:application, :group, :created)

  # Creates the app and the group, or updates them. Safe to run more than
  # once: an existing app keeps its client id and secret.
  # email_domains: nil keeps the domains of an existing app (an admin may
  # have changed them), and gives a new app DEFAULT_EMAIL_DOMAINS.
  def self.ensure!(redirect_uri:, email_domains: nil)
    raise ArgumentError, "redirect_uri must be an https URL from the Google Admin console" unless redirect_uri.to_s.start_with?("https://")

    Doorkeeper::Application.transaction do
      group = Group.find_or_create_by!(slug: GROUP_SLUG) do |new_group|
        new_group.name = NAME
        new_group.description = "People who sign in to Google Workspace through Weave."
        new_group.kind = "manual"
      end

      application = Doorkeeper::Application.find_or_initialize_by(name: NAME)
      created = application.new_record?
      domains = email_domains || (created ? DEFAULT_EMAIL_DOMAINS : application.email_domains)
      domains_before = application.email_domains
      application.assign_attributes(
        redirect_uri: redirect_uri,
        scopes: SCOPES,
        confidential: true,
        access_policy: "restricted",
        email_domains: domains.map { |domain| domain.to_s.strip.downcase.delete_prefix("@") }.compact_blank
      )
      application.save!
      RevokeLostAppAccessJob.perform_later(application_id: application.id) if !created && application.email_domains != domains_before

      ApplicationAccessGrant.find_or_create_by!(application: application, grantee: group)
      Result.new(application:, group:, created:)
    end
  end
end
