# frozen_string_literal: true

# Google Workspace as an OIDC client. See docs/ACTIVE_DIRECTORY.md.
namespace :google_workspace do
  desc "Create or update the Google Workspace OAuth app. REDIRECT_URI=<from the Google SSO profile> [EMAIL_DOMAINS=a.org,b.dev]"
  task setup: :environment do
    redirect_uri = ENV.fetch("REDIRECT_URI") { abort "Set REDIRECT_URI to the redirect URI that the Google SSO profile shows." }
    domains = ENV["EMAIL_DOMAINS"].to_s.split(",").map(&:strip).compact_blank.presence || GoogleWorkspaceApp::DEFAULT_EMAIL_DOMAINS

    result = GoogleWorkspaceApp.ensure!(redirect_uri: redirect_uri, email_domains: domains)
    application = result.application

    puts result.created ? "Created #{application.name}." : "Updated #{application.name}."
    puts "Issuer:        #{Doorkeeper::OpenidConnect.configuration.issuer.call(nil, nil) rescue Weave.url}"
    puts "Client ID:     #{application.uid}"
    puts "Client secret: read it on the admin page, /admin/oauth_applications/#{application.to_param}"
    puts "Email domains: #{application.email_domains.join(', ')}"
    puts "Google sign-in group: #{result.group.slug} (add people at /admin/groups/#{result.group.slug})"
  end
end
