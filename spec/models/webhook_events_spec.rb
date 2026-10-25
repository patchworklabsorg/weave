# frozen_string_literal: true

require "rails_helper"

# The models emit the webhook events in Service::Webhook::EVENT_TYPES. Each
# example registers a webhook for the event and reads what it would receive.
RSpec.describe "Webhook events" do # rubocop:disable RSpec/DescribeClass
  def listen(event) = create(:service_webhook, event_type: event)

  def sent(event)
    WebhookDelivery.where(event: event).order(:id).map { |delivery| JSON.parse(delivery.payload)["data"] }
  end

  describe "group membership" do
    let(:admin) { create(:user, :superadmin) }
    let(:user) { create(:user) }
    let(:group) { create(:group, slug: "eng") }

    before do
      listen("group.member_added")
      listen("group.member_removed")
      # The superadmin joins the admins system group on create.
      [admin, user, group]
      WebhookDelivery.delete_all
    end

    it "sends group.member_added for a manual add, with the actor and expiry" do
      expires_at = 1.week.from_now.change(usec: 0)
      expect { group.memberships.create!(user:, added_by: admin, source: "manual", expires_at:) }
        .to have_enqueued_job(DeliverWebhookJob)

      expect(sent("group.member_added")).to contain_exactly(
        "group"      => { "id" => group.public_id, "slug" => "eng" },
        "user"       => { "id" => user.p_id },
        "source"     => "manual",
        "reason"     => "added",
        "expires_at" => expires_at.iso8601,
        "actor"      => { "id" => admin.p_id }
      )
    end

    it "sends group.member_removed for a manual removal, with the PaperTrail actor" do
      membership = create(:group_membership, group:, user:)

      PaperTrail.request(whodunnit: admin.id) { membership.destroy! }

      expect(sent("group.member_removed")).to contain_exactly(
        include("user" => { "id" => user.p_id }, "source" => "manual", "reason" => "removed", "actor" => { "id" => admin.p_id })
      )
    end

    it "sends both events for a system sync" do
      user.update!(role: "admin")
      expect(sent("group.member_added")).to include(
        include("group" => include("slug" => "admins"), "user" => { "id" => user.p_id }, "source" => "system", "actor" => nil)
      )

      user.update!(role: "user")
      expect(sent("group.member_removed")).to contain_exactly(
        include("group" => include("slug" => "admins"), "source" => "system", "reason" => "removed")
      )
    end

    it "sends group.member_removed with reason expired from the expiry job" do
      create(:group_membership, group:, user:, expires_at: 1.hour.from_now)

      travel(2.hours) { ExpireGroupMembershipsJob.perform_now }

      expect(sent("group.member_removed")).to contain_exactly(include("reason" => "expired", "actor" => nil))
    end

    it "sends group.member_removed for each member when the group is deleted" do
      other = create(:user)
      create(:group_membership, group:, user:)
      create(:group_membership, group:, user: other)

      group.destroy

      expect(sent("group.member_removed")).to contain_exactly(
        include("user" => { "id" => user.p_id }, "reason" => "group_deleted", "group" => include("slug" => "eng")),
        include("user" => { "id" => other.p_id }, "reason" => "group_deleted")
      )
    end

    it "sends group.member_removed when the account is deleted" do
      create(:group_membership, group:, user:)
      p_id = user.p_id

      user.destroy!

      expect(sent("group.member_removed")).to contain_exactly(include("user" => { "id" => p_id }, "reason" => "account_deleted"))
    end
  end

  describe "users" do
    it "sends user.created" do
      listen("user.created")

      user = create(:user, first_name: "ada", last_name: "lovelace")

      expect(sent("user.created")).to contain_exactly(
        "user" => {
          "id" => user.p_id, "name" => "Ada Lovelace", "email" => user.email,
          "email_verified" => user.email_verified?, "slack_id" => user.slack_id, "active" => true
        }
      )
    end

    it "sends user.updated with the changed fields, and nothing for other columns" do
      user = create(:user)
      listen("user.updated")

      user.update!(slack_title: "Engineer", pronouns: "she/her")
      expect(sent("user.updated")).to be_empty

      user.update!(first_name: "Grace", locked_at: Time.current)
      expect(sent("user.updated")).to contain_exactly(
        include("user" => include("name" => a_string_starting_with("Grace"), "active" => false), "changed" => %w[name active])
      )
    end

    it "sends user.deleted with the ID only" do
      user = create(:user)
      listen("user.deleted")
      p_id = user.p_id

      user.destroy!

      expect(sent("user.deleted")).to contain_exactly("user" => { "id" => p_id })
    end

    it "cancels the queued user.updated deliveries of a deleted account, so the name and email are not sent" do
      user = create(:user)
      listen("user.updated")
      listen("user.deleted")
      user.update!(first_name: "Grace")
      other = create(:user)
      other.update!(first_name: "Ada")
      queued = WebhookDelivery.where(event: "user.updated").index_by(&:subject_id)

      user.destroy!

      expect(queued[user.p_id].reload).to be_cancelled
      expect(queued[user.p_id].payload).to be_nil
      expect(queued[other.p_id].reload).to be_pending
      expect(WebhookDelivery.find_by(event: "user.deleted")).to be_pending
    end
  end

  describe "sessions" do
    let(:user) { create(:user) }

    def open_session
      user.user_sessions.create!(session_token: SecureRandom.hex(16), expiration_at: 1.day.from_now)
    end

    it "sends session.created without the IP or location" do
      listen("session.created")

      session = open_session

      data = sent("session.created").sole
      expect(data).to include("user" => { "id" => user.p_id }, "session" => include("id" => session.public_id, "impersonated" => false))
      expect(data.to_json).not_to include("ip", "latitude")
    end

    it "sends session.expired when the session is signed out, once" do
      session = open_session
      listen("session.expired")

      session.update!(signed_out_at: Time.current, expiration_at: Time.current)
      session.update!(last_seen_at: Time.current)
      session.update!(expiration_at: Time.current)

      expect(sent("session.expired")).to contain_exactly(include("session" => include("id" => session.public_id, "ended_by" => "sign_out")))
    end

    it "sends session.expired from the job when the session runs out of time, once" do
      session = open_session
      listen("session.expired")

      travel(25.hours) do
        NotifyExpiredSessionsJob.perform_now
        NotifyExpiredSessionsJob.perform_now
        session.reload.update!(signed_out_at: Time.current, expiration_at: Time.current)
      end

      expect(sent("session.expired")).to contain_exactly(include("session" => include("id" => session.public_id, "ended_by" => "time")))
    end

    it "sends nothing from the job for a session that ended more than a day ago" do
      open_session
      listen("session.expired")

      travel(3.days) { NotifyExpiredSessionsJob.perform_now }

      expect(sent("session.expired")).to be_empty
    end
  end
end
