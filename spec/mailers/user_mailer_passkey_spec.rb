# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserMailer do
  let(:user) { create(:user, :verified) }

  describe "#passkey_added" do
    it "names the passkey and links to the passkeys page" do
      passkey = register_passkey(user, nickname: "Work laptop")

      mail = described_class.passkey_added(passkey)

      expect(mail.to).to eq([user.email])
      expect(mail.subject).to include("A passkey was added to your account")
      expect(mail.text_part.body.to_s).to include("Work laptop").and include("/profile/passkeys")
      expect(mail.html_part.body.to_s).to include("Work laptop")
    end
  end

  describe "#passkey_removed" do
    it "names the removed passkey" do
      mail = described_class.passkey_removed(user, "Old phone")

      expect(mail.to).to eq([user.email])
      expect(mail.subject).to include("A passkey was removed from your account")
      expect(mail.text_part.body.to_s).to include("Old phone")
    end
  end

  describe "#social_profile_linked" do
    it "names the account and links to the social profiles page" do
      mail = described_class.social_profile_linked(user, "GitHub", "octocat")

      expect(mail.to).to eq([user.email])
      expect(mail.subject).to include("A GitHub account was linked to your account")
      expect(mail.text_part.body.to_s).to include("octocat").and include("/profile/social")
      expect(mail.html_part.body.to_s).to include("octocat")
    end
  end
end
