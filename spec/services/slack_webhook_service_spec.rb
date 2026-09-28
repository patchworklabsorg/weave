# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackWebhookService do
  describe ".process_user_change" do
    # Magic links go to users.email. If Slack could change it, anyone who can
    # edit a Slack profile could redirect the user's sign-in.
    it "never changes the primary email, and adds the Slack email as an unconfirmed secondary" do
      user = create(:user, :verified, slack_id: "U123", email: "old@example.com")

      expect do
        described_class.process_user_change(
          "id"      => "U123",
          "profile" => { "email" => "New@Example.com" }
        )
      end.to have_enqueued_job(EmailAddressConfirmationJob)

      user.reload
      expect(user.email).to eq("old@example.com")
      expect(user.email_verified?).to be true

      address = user.email_addresses.find_by(email: "new@example.com")
      expect(address).to be_present
      expect(address).not_to be_confirmed
      expect(address).not_to be_primary
    end

    it "tells the primary address that a new address was added" do
      create(:user, :verified, slack_id: "U321", email: "old@example.com")

      expect do
        described_class.process_user_change("id" => "U321", "profile" => { "email" => "new@example.com" })
      end.to have_enqueued_mail(UserMailer, :slack_email_address_added)
    end

    it "doesn't send the notice when the email is unchanged" do
      create(:user, :verified, slack_id: "U322", email: "same@example.com")

      expect do
        described_class.process_user_change("id" => "U322", "profile" => { "email" => "same@example.com" })
      end.not_to have_enqueued_mail(UserMailer, :slack_email_address_added)
    end

    it "doesn't let the unconfirmed Slack email be used to request a magic link" do
      user = create(:user, :verified, slack_id: "U124", email: "old@example.com")

      described_class.process_user_change("id" => "U124", "profile" => { "email" => "new@example.com" })

      expect(User.find_for_any_email("new@example.com")).to be_nil
      expect(User.find_for_any_email("old@example.com")).to eq(user)
    end

    it "does nothing to the email when it is unchanged" do
      user = create(:user, :verified, slack_id: "U777", email: "same@example.com")

      expect do
        described_class.process_user_change(
          "id"      => "U777",
          "profile" => { "email" => "same@example.com" }
        )
      end.not_to change(EmailAddress, :count)

      expect(user.reload.email_verified?).to be true
    end

    it "doesn't add the address again when the user already has it" do
      user = create(:user, :verified, slack_id: "U555", email: "old@example.com")
      user.email_addresses.create!(email: "second@example.com")

      expect do
        described_class.process_user_change("id" => "U555", "profile" => { "email" => "second@example.com" })
      end.not_to change(EmailAddress, :count)
    end

    it "skips an email that belongs to another user and still applies name changes" do
      create(:user, :verified, email: "taken@example.com")
      user = create(:user, :verified, slack_id: "U999", email: "mine@example.com", first_name: "Old")

      expect do
        described_class.process_user_change(
          "id"      => "U999",
          "profile" => { "email" => "taken@example.com", "first_name" => "New" }
        )
      end.not_to change(EmailAddress, :count)

      user.reload
      expect(user.email).to eq("mine@example.com")
      expect(user.first_name).to eq("New")
    end
  end
end
