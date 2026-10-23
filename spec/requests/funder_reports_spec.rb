# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Funder reports and consent", type: :request do
  describe "the admin preview" do
    it "lists the funder profiles and previews one report for an admin" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get admin_funder_reports_path
      expect(response.body).to include("Consent Funder", "Test Funder")

      get admin_funder_report_path("consent_funder")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Preview only", "TEST-2027-001", "totals (sums only)", "required", "ages 13 to 18")
    end

    it "keeps the page from members" do
      sign_in_via_magic_link(create(:user, :verified))

      get admin_funder_report_path("consent_funder")

      expect(response).to redirect_to(login_path)
    end

    it "sends an unknown funder back to the list" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get admin_funder_report_path("nobody")

      expect(response).to redirect_to(admin_funder_reports_path)
    end
  end

  describe "member consent" do
    let(:member) { create(:user, :verified) }

    before { sign_in_via_magic_link(member) }

    it "shows each funder that asks for consent and lets the member give and withdraw it" do
      get demographics_path
      expect(response.body).to include("Funders that ask for your consent", "Consent Funder")
      expect(response.body).not_to include("Test Funder")

      post funder_consents_path(funder: "consent_funder")
      expect(member.funder_consents.live.pluck(:funder)).to eq(["consent_funder"])

      delete funder_consent_path("consent_funder")
      expect(member.funder_consents.live).to be_empty
    end

    it "refuses consent for a funder that does not ask for it" do
      post funder_consents_path(funder: "test_funder")

      expect(member.funder_consents).to be_empty
      expect(flash[:alert]).to eq(I18n.t("funder_consents.unknown"))
    end
  end
end
