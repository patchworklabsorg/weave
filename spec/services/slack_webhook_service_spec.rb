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

    it "makes a guest a member when Slack reports the promotion" do
      user = create(:user, slack_id: "U500", email: "guest@example.com")

      described_class.process_user_change("id" => "U500", "profile" => { "email" => "guest@example.com" })

      expect(user.reload).to be_slack_member
    end

    it "keeps a guest pending while Slack still reports them as a guest" do
      user = create(:user, slack_id: "U501", email: "guest@example.com")

      described_class.process_user_change(
        "id" => "U501", "is_ultra_restricted" => true, "profile" => { "email" => "guest@example.com" }
      )

      expect(user.reload).to be_slack_pending
    end

    it "ends the membership of a deactivated Slack account" do
      user = create(:user, slack_id: "U502", slack_membership: "member")

      described_class.process_user_change("id" => "U502", "deleted" => true, "profile" => {})

      expect(user.reload).to be_slack_pending
    end
  end

  describe ".process_team_join" do
    before { allow(SlackService).to receive(:new).and_return(instance_double(SlackService, post_code_of_conduct: true)) }

    it "links an invited signup who joins as a guest, and keeps them pending" do
      user = create(:user, :verified, email: "new@example.com", slack_invited_at: 1.hour.ago)

      described_class.process_team_join(
        "id" => "U600", "is_restricted" => true, "is_ultra_restricted" => true, "profile" => { "email" => "new@example.com" }
      )

      user.reload
      expect(user.slack_id).to eq("U600")
      expect(user).to be_slack_pending
      expect(user.slack_onboarding_step).to eq(:accept_code_of_conduct)
    end

    it "makes someone who joins as a regular member a member" do
      user = create(:user, :verified, email: "full@example.com")

      described_class.process_team_join("id" => "U601", "profile" => { "email" => "full@example.com" })

      expect(user.reload).to be_slack_member
    end

    it "creates a pending account for a guest who joins without a Weave account" do
      user = described_class.process_team_join(
        "id" => "U602", "is_ultra_restricted" => true,
        "profile" => { "email" => "walkin@example.com", "real_name" => "Walk In" }
      )

      expect(user).to be_slack_pending
    end
  end
end
