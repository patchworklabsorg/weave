# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletionReviewReminderJob do
  it "emails the identity team leads about requests past their review date" do
    lead = create(:user, :identity_lead)
    overdue = travel_to(15.days.ago) { create(:deletion_request) }
    create(:deletion_request)

    expect { described_class.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([lead.email])
    expect(mail.body.encoded).to include(overdue.public_id)
  end

  it "sends nothing when every review is on time" do
    create(:user, :identity_lead)
    create(:deletion_request)

    expect { described_class.perform_now }.not_to(change { ActionMailer::Base.deliveries.size })
  end
end
