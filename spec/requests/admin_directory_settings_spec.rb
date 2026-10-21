# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin settings for Google Workspace and sponsored projects", type: :request do
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:admin) { create(:user, :admin, :verified) }
  let(:application) { Doorkeeper::Application.create!(name: "Google Workspace", redirect_uri: "https://accounts.google.com/cb", scopes: "openid email profile") }

  describe "PATCH email_domains" do
    it "lets a superadmin set the email domains" do
      sign_in_via_magic_link(superadmin)

      patch email_domains_admin_oauth_application_path(application), params: { email_domains: "PatchworkLabs.org, @hackboston.dev" }

      expect(application.reload.email_domains).to eq(%w[patchworklabs.org hackboston.dev])
    end

    it "refuses a value that is not a domain" do
      sign_in_via_magic_link(superadmin)

      patch email_domains_admin_oauth_application_path(application), params: { email_domains: "not a domain!" }

      expect(application.reload.email_domains).to be_empty
      expect(flash[:alert]).to include("is not a domain")
    end

    it "is superadmin only" do
      sign_in_via_magic_link(admin)

      patch email_domains_admin_oauth_application_path(application), params: { email_domains: "patchworklabs.org" }

      expect(application.reload.email_domains).to be_empty
    end
  end

  describe "group waivers" do
    it "lets a superadmin mark a group as a sponsored project" do
      group = create(:group, name: "HackBoston")
      sign_in_via_magic_link(superadmin)

      patch admin_group_path(group), params: { group: { name: "HackBoston", waives_code_of_conduct: "1", waives_slack: "1" } }

      expect(group.reload).to have_attributes(waives_code_of_conduct: true, waives_slack: true)
    end
  end
end
