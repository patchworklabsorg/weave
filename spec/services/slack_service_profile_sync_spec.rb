# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackService do
  let(:user_client) { instance_double(Slack::Web::Client) }

  def service_with(user_client)
    described_class.allocate.tap { |service| service.instance_variable_set(:@user_client, user_client) }
  end

  def custom_fields(values)
    values.to_h { |attr, value| [described_class::SHARED_CUSTOM_FIELDS.fetch(attr), { "value" => value }] }
  end

  describe "#sync_slack_users_to_idp profile fields" do
    let(:member) { { "id" => "U800", "updated" => 1.year.ago.to_i, "profile" => { "email" => "sync@example.com" } } }

    def stub_full_profile(profile)
      allow(user_client).to receive(:users_profile_get).with(user: "U800").and_return("ok" => true, "profile" => profile)
    end

    def sync(client = user_client)
      service = service_with(client)
      allow(service).to receive_messages(configured?: true, list_members: [member.deep_dup])
      service.sync_slack_users_to_idp
    end

    it "clears fields that were cleared in Slack" do
      user = create(:user, :verified, email: "sync@example.com", slack_id: "U800",
                                      slack_cost_center: "CC-1", slack_department: "Ops", slack_title: "Lead")
      stub_full_profile("title" => "", "fields" => custom_fields(slack_department: "Ops"))

      sync

      user.reload
      expect([user.slack_cost_center, user.slack_department, user.slack_title]).to eq([nil, "Ops", nil])
    end

    it "clears every custom field when Slack sends an empty fields array" do
      user = create(:user, :verified, email: "sync@example.com", slack_id: "U800", slack_cost_center: "CC-1")
      stub_full_profile("fields" => [])

      sync

      expect(user.reload.slack_cost_center).to be_nil
    end

    it "keeps custom fields when the full profile cannot be read" do
      user = create(:user, :verified, email: "sync@example.com", slack_id: "U800", slack_cost_center: "CC-1")
      allow(user_client).to receive(:users_profile_get).and_raise(Slack::Web::Api::Errors::SlackError, "fatal_error")

      sync

      expect(user.reload.slack_cost_center).to eq("CC-1")
    end

    it "keeps custom fields without a user token" do
      user = create(:user, :verified, email: "sync@example.com", slack_id: "U800", slack_cost_center: "CC-1")

      sync(nil)

      expect(user.reload.slack_cost_center).to eq("CC-1")
    end

    it "reads Slack edits on a second run within the hour" do
      user = create(:user, :verified, email: "sync@example.com", slack_id: "U800")
      stub_full_profile("fields" => custom_fields(slack_cost_center: "CC-1"))
      sync
      stub_full_profile("fields" => custom_fields(slack_cost_center: "CC-2"))

      expect(sync).to eq(synced: 1, skipped: 0)
      expect(user.reload.slack_cost_center).to eq("CC-2")
    end

    it "counts a member with no changes as skipped" do
      create(:user, :verified, email: "sync@example.com", slack_id: "U800", slack_membership: "member")
      stub_full_profile("fields" => [])
      sync

      expect(sync).to eq(synced: 0, skipped: 1)
    end

    it "clears a manager that Slack no longer shows" do
      manager = create(:user, :verified, slack_id: "U900", is_staff: true)
      user = create(:user, :verified, email: "sync@example.com", slack_id: "U800", is_staff: true, manager: manager)
      stub_full_profile("fields" => [])

      sync

      expect(user.reload.manager).to be_nil
    end

    it "keeps a manager who has no Slack account" do
      manager = create(:user, :verified, is_staff: true)
      user = create(:user, :verified, email: "sync@example.com", slack_id: "U800", is_staff: true, manager: manager)
      stub_full_profile("fields" => [])

      sync

      expect(user.reload.manager).to eq(manager)
    end
  end

  describe "#sync_idp_users_to_slack" do
    it "pushes only the PWL ID, not the profile fields" do
      user = create(:user, :verified, email: "push@example.com", slack_id: "U801", slack_cost_center: "CC-OLD")
      service = service_with(user_client)
      allow(service).to receive_messages(configured?: true, find_user_by_email: nil)
      allow(service).to receive(:find_user_by_email).with(user.email).and_return("id" => "U801", "updated" => 0)
      pushed = []
      allow(user_client).to receive(:users_profile_set) { |args| pushed << args[:profile] }

      service.sync_idp_users_to_slack

      expect(pushed).not_to include(a_string_including("CC-OLD"))
    end
  end

  describe "#push_profile_fields" do
    def pushed_profile(user)
      profile = nil
      allow(user_client).to receive(:users_profile_set) { |args| profile = JSON.parse(args[:profile]) }
      service_with(user_client).push_profile_fields("U802", user)
      profile
    end

    it "sends blank values so Slack clears them" do
      user = build(:user, slack_title: "Lead", slack_cost_center: nil)

      profile = pushed_profile(user)

      expect(profile["title"]).to eq("Lead")
      expect(profile.dig("fields", described_class::SHARED_CUSTOM_FIELDS[:slack_cost_center], "value")).to eq("")
      expect(profile.dig("fields", described_class::MANAGER_FIELD, "value")).to eq("")
    end

    it "sends the manager's Slack ID" do
      user = build(:user, manager: build(:user, slack_id: "U903"))

      expect(pushed_profile(user).dig("fields", described_class::MANAGER_FIELD, "value")).to eq("U903")
    end

    it "leaves out a manager who has no Slack account" do
      user = create(:user, manager: create(:user))

      expect(pushed_profile(user)["fields"]).not_to have_key(described_class::MANAGER_FIELD)
    end

    it "raises Slack errors so the job can retry" do
      allow(user_client).to receive(:users_profile_set).and_raise(Slack::Web::Api::Errors::SlackError, "fatal_error")

      expect { service_with(user_client).push_profile_fields("U802", build(:user)) }
        .to raise_error(Slack::Web::Api::Errors::SlackError)
    end

    it "does nothing without a user token" do
      expect(service_with(nil).push_profile_fields("U802", build(:user))).to be false
    end
  end
end
