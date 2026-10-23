# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataHandlingMailer do
  let(:user) { create(:user, :verified, first_name: "Ada") }

  it "sends the deletion receipt with what was removed, what was retained and why, and no history" do
    request = create(:deletion_request, user:, receipt: {
                       "removed"   => %w[account_profile guardian_contact],
                       "retained"  => %w[verification_audit financial knot],
                       "none_held" => %w[funder_records]
                     })

    mail = described_class.deletion_receipt(request)
    body = mail.body.encoded

    expect(mail.to).to eq([user.email])
    expect(body).to include("Account and profile", "Verification records", "3 years", "Grant payments", "7 years",
                            "The Knot", "Records a funder requires", Weave.data_page_url)
    expect { mail.deliver_now }.not_to change(Ahoy::Message, :count)
  end

  it "links the data page from every email, the guardian emails too" do
    consent = create(:guardian_consent)

    [
      described_class.takeout_ready(create(:takeout_request, user:, status: "ready", expires_at: 1.day.from_now)),
      described_class.deletion_requested(create(:deletion_request, user:)),
      described_class.dormancy_warning(user, days_before: 60, deadline: 60.days.from_now),
      GuardianConsentMailer.request_consent(consent, "token"),
      GuardianConsentMailer.granted(consent)
    ].each do |mail|
      expect(mail.html_part.body.encoded).to include(Weave.data_page_url)
      expect(mail.text_part.body.encoded).to include(Weave.data_page_url)
    end
  end

  it "warns a dormant member with the date" do
    mail = described_class.dormancy_warning(user, days_before: 7, deadline: Time.zone.local(2031, 6, 1))

    expect(mail.subject).to include("7 days")
    expect(mail.text_part.decoded.squish).to include(Date.new(2031, 6, 1).to_fs(:long))
  end
end
