# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuardianConsentMailer, type: :mailer do
  let(:user) { create(:user, :verified, :minor, first_name: "Ada", email: "ada@example.com") }
  let(:consent) { create(:guardian_consent, user:, guardian_email: "grace@example.org") }

  describe "#request_consent" do
    subject(:mail) { described_class.request_consent(consent, "the-token") }

    it "goes to the guardian with the consent link" do
      expect(mail.to).to eq(["grace@example.org"])
      expect(mail.subject).to include("Ada asks for your consent")
      expect(mail.body.encoded).to include("/guardian/the-token")
    end
  end

  describe "#receipt" do
    subject(:mail) { described_class.receipt(consent, "the-token") }

    it "gives the guardian the link to take the consent back" do
      expect(mail.to).to eq(["grace@example.org"])
      expect(mail.body.encoded).to include("/guardian/the-token")
    end
  end

  describe "#granted" do
    it "tells the member" do
      mail = described_class.granted(consent)

      expect(mail.to).to eq(["ada@example.com"])
      expect(mail.body.encoded).to include("/slack")
    end
  end

  describe "#revoked" do
    it "tells the member" do
      expect(described_class.revoked(consent).to).to eq(["ada@example.com"])
    end
  end
end
