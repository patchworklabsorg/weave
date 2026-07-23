# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackWebhookService do
  describe ".process_user_change" do
    it "clears email confirmation when the Slack email changes" do
      user = create(:user, :verified, slack_id: "U123", email: "old@example.com")
      expect(user.email_verified?).to be true

      described_class.process_user_change(
        "id"      => "U123",
        "profile" => { "email" => "new@example.com" }
      )

      user.reload
      expect(user.email).to eq("new@example.com")
      expect(user.email_confirmed_at).to be_nil
      expect(user.email_verified?).to be false
    end

    it "leaves confirmation intact when the email is unchanged" do
      user = create(:user, :verified, slack_id: "U777", email: "same@example.com")

      described_class.process_user_change(
        "id"      => "U777",
        "profile" => { "email" => "same@example.com" }
      )

      expect(user.reload.email_verified?).to be true
    end
  end
end
