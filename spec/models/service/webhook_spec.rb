# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: service_webhooks
# Database name: primary
#
#  id                :bigint           not null, primary key
#  event_type        :string           not null
#  failure_count     :integer          default(0)
#  last_triggered_at :datetime
#  secret_token      :string
#  status            :string           default("active"), not null
#  url               :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  created_by_id     :bigint           not null
#  service_id        :bigint           not null
#
# Indexes
#
#  index_service_webhooks_on_created_by_id              (created_by_id)
#  index_service_webhooks_on_service_id                 (service_id)
#  index_service_webhooks_on_service_id_and_event_type  (service_id,event_type)
#  index_service_webhooks_on_status                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (service_id => services.id)
#
RSpec.describe Service::Webhook do
  it "accepts the group membership events" do
    expect(described_class::EVENT_TYPES).to include("group.member_added", "group.member_removed")
    expect(build(:service_webhook, event_type: "group.member_removed")).to be_valid
  end

  it "rejects an event that Weave does not send" do
    webhook = build(:service_webhook, event_type: "user.exploded")

    expect(webhook).not_to be_valid
    expect(webhook.errors[:event_type]).to be_present
  end

  it "needs an https URL in production" do
    allow(Rails.env).to receive(:production?).and_return(true)

    expect(build(:service_webhook, url: "http://hooks.example.com/")).not_to be_valid
    expect(build(:service_webhook, url: "https://hooks.example.com/")).to be_valid
  end

  it "turns off after 10 failures" do
    webhook = create(:service_webhook, failure_count: 8)

    webhook.record_failure!
    expect(webhook).to be_active

    webhook.record_failure!
    expect(webhook.reload).to be_inactive
  end
end
