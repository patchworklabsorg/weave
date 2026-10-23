# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationMailer do
  let(:member) { create(:user, :verified, first_name: "Ada") }

  describe "#status_changed" do
    it "gives the note after a document problem, and links the data page" do
      verification = create(:verification, user: member, status: "needs_resubmission", resubmission_note: "The photo is blurry.")

      mail = described_class.status_changed(verification)

      expect(mail.to).to eq([member.email])
      expect(mail.subject).to include(I18n.t("verification.mailer.needs_resubmission.subject"))
      expect(mail.body.encoded).to include("The photo is blurry.", Weave.data_page_url)
    end

    it "says the document is OK and that the team will agree a call time" do
      verification = create(:verification, :awaiting_call, user: member)

      mail = described_class.status_changed(verification)
      expect(mail.subject).to include(I18n.t("verification.mailer.awaiting_call.subject"))
      expect(mail.body.encoded).to include("email or Slack")
    end

    it "gives the call time" do
      verification = create(:verification, :call_scheduled, user: member, call_scheduled_for: Time.zone.local(2026, 11, 3, 15, 30))

      expect(described_class.status_changed(verification).body.encoded).to include("November 3, 2026 at 15:30 UTC", "We do not record the call")
    end

    it "gives the retry date after a fail" do
      verification = create(:verification, :failed, user: member)

      expect(described_class.status_changed(verification).body.encoded).to include(verification.retry_available_at.to_date.to_fs(:long))
    end

    it "says when the lead reviews the attempts" do
      verification = create(:verification, :failed, user: member, escalated_at: 1.hour.ago)

      expect(described_class.status_changed(verification).subject).to include(I18n.t("verification.mailer.escalated.subject"))
    end
  end

  describe "#escalated" do
    it "tells the lead without the member's name" do
      verification = create(:verification, :failed, user: member, escalated_at: 1.hour.ago)
      lead = create(:user, :identity_lead)

      mail = described_class.escalated(verification, lead)

      expect(mail.to).to eq([lead.email])
      expect(mail.body.encoded).to include(member.p_id)
      expect(mail.body.encoded).not_to include("Ada")
    end
  end
end
