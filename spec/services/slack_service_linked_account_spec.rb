# frozen_string_literal: true

require "rails_helper"

# A Weave user has one Slack account. A second account that matches one of
# their addresses (for example, one made under a secondary address) must not
# take the link, the Weave ID or the profile.
RSpec.describe SlackService do
  let(:client) { instance_double(Slack::Web::Client) }
  let(:user_client) { instance_double(Slack::Web::Client) }
  let(:service) do
    described_class.allocate.tap do |service|
      service.instance_variable_set(:@client, client)
      service.instance_variable_set(:@user_client, user_client)
    end
  end
  let(:pushed_to) { [] }

  before do
    allow(service).to receive(:configured?).and_return(true)
    allow(user_client).to receive(:team_profile_get)
      .and_return("ok" => true, "profile" => { "fields" => [{ "id" => "Xf_weave", "label" => described_class::PWL_ID_FIELD }] })
    allow(user_client).to receive(:users_profile_set) { |args| pushed_to << args[:user] }
  end

  def slack_account(id, deleted: false)
    allow(client).to receive(:users_info).with(user: id).and_return("ok" => true, "user" => { "id" => id, "deleted" => deleted })
  end

  describe "#other_account_linked?" do
    let(:user) { build(:user, slack_id: "U1") }

    it "is true for a second account while the linked account is in the workspace" do
      slack_account("U1")

      expect(service.other_account_linked?(user, "U2")).to be(true)
    end

    it "is false for the linked account" do
      expect(service.other_account_linked?(user, "U1")).to be(false)
    end

    it "is false for a user with no linked account" do
      expect(service.other_account_linked?(build(:user, slack_id: nil), "U2")).to be(false)
    end

    it "is false when the linked account was deactivated" do
      slack_account("U1", deleted: true)

      expect(service.other_account_linked?(user, "U2")).to be(false)
    end

    it "keeps the linked account when Slack can't say" do
      allow(client).to receive(:users_info).and_raise(Slack::Web::Api::Errors::SlackError, "ratelimited")

      expect(service.other_account_linked?(user, "U2")).to be(true)
    end

    it "raises when Slack can't say and the caller asks for strict" do
      allow(client).to receive(:users_info).and_raise(Slack::Web::Api::Errors::SlackError, "ratelimited")

      expect { service.other_account_linked?(user, "U2", strict: true) }.to raise_error(described_class::ApiError)
    end

    it "is false when Slack no longer knows the linked account" do
      allow(client).to receive(:users_info).and_raise(Slack::Web::Api::Errors::UserNotFound, "user_not_found")

      expect(service.other_account_linked?(user, "U2")).to be(false)
    end
  end

  describe "#sync_weave_id" do
    it "sends the Weave ID to the linked account, not to a second account found by email" do
      user = create(:user, :verified, email: "adam@patchworklabs.org", slack_id: "U1")
      slack_account("U1")
      allow(service).to receive(:find_user_by_email).with(user.email).and_return("id" => "U2", "updated" => 0)

      expect(service.sync_weave_id(user)).to be(true)

      expect(user.reload.slack_id).to eq("U1")
      expect(pushed_to).to eq(["U1"])
    end

    it "links the account found by email when the user has none" do
      user = create(:user, :verified, email: "new@example.com", slack_id: nil)
      allow(service).to receive(:find_user_by_email).with(user.email).and_return("id" => "U3", "updated" => 0)

      service.sync_weave_id(user)

      expect(user.reload.slack_id).to eq("U3")
      expect(pushed_to).to eq(["U3"])
    end

    it "moves the link to the account found by email when the linked one was deactivated" do
      user = create(:user, :verified, email: "moved@example.com", slack_id: "U1", slack_joined_at: 2.years.ago)
      slack_account("U1", deleted: true)
      joined = 1.day.ago.to_i
      allow(service).to receive(:find_user_by_email).with(user.email).and_return("id" => "U4", "updated" => joined)

      service.sync_weave_id(user)

      user.reload
      expect(user.slack_id).to eq("U4")
      expect(user.slack_joined_at.to_i).to eq(joined)
      expect(pushed_to).to eq(["U4"])
    end

    it "sends the Weave ID to the linked account when the email no longer finds it" do
      user = create(:user, :verified, email: "changed@example.com", slack_id: "U1")
      slack_account("U1")
      allow(service).to receive(:find_user_by_email).and_return(nil)

      expect(service.sync_weave_id(user)).to be(true)
      expect(pushed_to).to eq(["U1"])
    end

    it "sends nothing when the email finds no account and the linked one is gone" do
      user = create(:user, :verified, email: "gone@example.com", slack_id: "U1")
      slack_account("U1", deleted: true)
      allow(service).to receive(:find_user_by_email).and_return(nil)

      expect(service.sync_weave_id(user)).to be(false)
      expect(pushed_to).to be_empty
    end

    it "keeps a guest found by email pending" do
      user = create(:user, :verified, email: "guest@example.com", slack_id: nil)
      allow(service).to receive(:find_user_by_email).and_return("id" => "U5", "updated" => 0, "is_ultra_restricted" => true)

      service.sync_weave_id(user)

      expect(user.reload).to be_slack_pending
    end

    it "makes someone Slack reports as a regular member a member" do
      user = create(:user, :verified, email: "full@example.com", slack_id: nil)
      allow(service).to receive(:find_user_by_email).and_return("id" => "U6", "updated" => 0)

      service.sync_weave_id(user)

      expect(user.reload).to be_slack_member
    end

    it "sends nothing for someone who is not in Slack" do
      user = create(:user, :verified, slack_id: nil)
      allow(service).to receive(:find_user_by_email).and_return(nil)

      expect(service.sync_weave_id(user)).to be(false)
      expect(pushed_to).to be_empty
    end
  end

  describe "#sync_slack_users_to_idp" do
    it "does not move the link or the profile to a second account" do
      user = create(:user, :verified, email: "adam@outlook.example", slack_id: "U1", slack_title: "Patch lead")
      slack_account("U1")
      second = { "id" => "U2", "updated" => 0, "profile" => { "email" => "adam@patchworklabs.org", "title" => "Something else" } }
      allow(User).to receive(:find_for_any_email).and_call_original
      allow(User).to receive(:find_for_any_email).with("adam@patchworklabs.org").and_return(user)
      allow(service).to receive(:list_members).and_return([second])
      allow(user_client).to receive(:users_profile_get).and_return("ok" => false)

      service.sync_slack_users_to_idp

      user.reload
      expect(user.slack_id).to eq("U1")
      expect(user.slack_title).to eq("Patch lead")
    end
  end
end
