# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin staging mail allowlist", type: :request do
  let(:owner) { create(:user, :owner, :verified) }

  context "when on staging" do
    before { allow(Weave).to receive(:staging?).and_return(true) }

    it "lets an owner add and remove an entry" do
      sign_in_via_magic_link(owner)

      post admin_staging_mail_allowlist_entries_path, params: { staging_mail_allowlist_entry: { entry: " Tester@Example.com " } }
      expect(response).to redirect_to(admin_staging_mail_allowlist_entries_path)
      entry = StagingMailAllowlistEntry.sole
      expect(entry).to have_attributes(entry: "tester@example.com", created_by: owner)

      get admin_staging_mail_allowlist_entries_path
      expect(response.body).to include("tester@example.com")

      delete admin_staging_mail_allowlist_entry_path(entry)
      expect(StagingMailAllowlistEntry.count).to eq(0)
    end

    it "refuses an entry that is not an address or a domain" do
      sign_in_via_magic_link(owner)

      post admin_staging_mail_allowlist_entries_path, params: { staging_mail_allowlist_entry: { entry: "example.com" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(StagingMailAllowlistEntry.count).to eq(0)
    end

    it "refuses a superadmin who is not an owner" do
      sign_in_via_magic_link(create(:user, :superadmin, :verified))

      get admin_staging_mail_allowlist_entries_path

      expect(response).to have_http_status(:not_found)
    end
  end

  it "does not exist outside staging" do
    sign_in_via_magic_link(owner)

    get admin_staging_mail_allowlist_entries_path

    expect(response).to have_http_status(:not_found)
  end
end
