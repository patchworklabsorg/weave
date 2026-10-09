# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "default state" do
    it "starts a new signup as pending" do
      expect(create(:user)).to be_slack_pending
    end
  end

  describe ".slack_membership_for" do
    it "makes a regular workspace account a member" do
      expect(described_class.slack_membership_for("id" => "U1")).to eq("member")
    end

    it "keeps a single-channel guest pending" do
      expect(described_class.slack_membership_for("id" => "U1", "is_ultra_restricted" => true)).to eq("pending")
    end

    it "keeps a multi-channel guest pending" do
      expect(described_class.slack_membership_for("id" => "U1", "is_restricted" => true)).to eq("pending")
    end

    it "does not count a deactivated account" do
      expect(described_class.slack_membership_for("id" => "U1", "deleted" => true)).to eq("pending")
    end
  end

  describe "#apply_slack_membership!" do
    it "promotes a guest that Slack reports as a regular member" do
      user = create(:user, slack_id: "U1")

      expect { user.apply_slack_membership!("id" => "U1") }.to change { user.reload.slack_membership }.to("member")
    end

    it "demotes a member that Slack reports as deactivated" do
      user = create(:user, slack_id: "U1", slack_membership: "member")

      user.apply_slack_membership!("id" => "U1", "deleted" => true)

      expect(user.reload).to be_slack_pending
    end

    it "ignores a Slack account other than the linked one" do
      user = create(:user, slack_id: "U1")

      user.apply_slack_membership!("id" => "U2")

      expect(user.reload).to be_slack_pending
    end
  end

  describe "#slack_onboarding_step" do
    it "asks a new account to request an invite" do
      expect(build(:user).slack_onboarding_step).to eq(:request_invite)
    end

    it "asks an invited account to accept the invite" do
      expect(build(:user, slack_invited_at: 1.hour.ago).slack_onboarding_step).to eq(:accept_invite)
    end

    it "asks a guest to accept the code of conduct" do
      expect(build(:user, slack_invited_at: 1.hour.ago, slack_id: "U1").slack_onboarding_step).to eq(:accept_code_of_conduct)
    end

    it "waits on the promotion after the guest accepts" do
      user = build(:user, slack_id: "U1", slack_coc_accepted_at: 1.minute.ago)

      expect(user.slack_onboarding_step).to eq(:awaiting_promotion)
    end

    it "is done for a full member who accepted the code of conduct" do
      user = build(:user, slack_id: "U1", slack_membership: "member", slack_coc_accepted_at: 1.day.ago)

      expect(user.slack_onboarding_step).to eq(:member)
      expect(user).to be_slack_onboarding_complete
    end

    it "asks a full member who joined before the code-of-conduct flow to accept it" do
      user = build(:user, slack_id: "U1", slack_membership: "member")

      expect(user.slack_onboarding_step).to eq(:accept_code_of_conduct)
      expect(user).not_to be_slack_onboarding_complete
    end
  end

  describe ".code_of_conduct_pending" do
    it "finds full members without an acceptance" do
      legacy = create(:user, slack_id: "U1", slack_membership: "member")
      create(:user, slack_id: "U2", slack_membership: "member", slack_coc_accepted_at: 1.day.ago)
      create(:user, slack_id: "U3")
      create(:user, slack_id: "U4", slack_membership: "member", code_of_conduct_exempt: true)
      create(:user)

      expect(described_class.code_of_conduct_pending).to contain_exactly(legacy)
    end
  end

  describe "#name_missing?" do
    it "is true for the names the Slack import makes up" do
      expect(build(:user, first_name: "NOTSET", last_name: "NOTSET")).to be_name_missing
      expect(build(:user, first_name: "Ada", last_name: "NOTSET")).to be_name_missing
      expect(build(:user, first_name: "Unknown", last_name: "User")).to be_name_missing
    end

    it "is false for a real name" do
      expect(build(:user, first_name: "Ada", last_name: "Lovelace")).not_to be_name_missing
    end

    it "matches the name_missing scope" do
      missing = create(:user, first_name: "NOTSET", last_name: "NOTSET")
      create(:user, first_name: "Ada", last_name: "Lovelace")

      expect(described_class.name_missing).to contain_exactly(missing)
    end
  end
end
