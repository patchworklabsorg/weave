# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: verifications
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  account_deleted_at        :datetime
#  age_consistent            :boolean
#  call_scheduled_for        :datetime
#  decided_at                :datetime
#  decision_reason           :text
#  document_purged_at        :datetime
#  document_type             :string
#  escalated_at              :datetime
#  escalation_note           :text
#  escalation_resolution     :string
#  escalation_resolved_at    :datetime
#  guardian_attended         :boolean          default(FALSE), not null
#  knot_review_reason        :string
#  pre_review_started_at     :datetime
#  pre_reviewed_at           :datetime
#  region_consistent         :boolean
#  resubmission_note         :text
#  status                    :string           default("submitted"), not null
#  verification_method       :string           default("document_call"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  call_scheduled_by_id      :bigint
#  escalation_resolved_by_id :bigint
#  guardian_consent_id       :bigint
#  knot_id                   :bigint
#  pre_reviewer_id           :bigint
#  previous_attempt_id       :bigint
#  second_verifier_id        :bigint
#  user_id                   :bigint
#  verifier_id               :bigint
#
# Indexes
#
#  index_verifications_on_account_deleted_at         (account_deleted_at)
#  index_verifications_on_call_scheduled_by_id       (call_scheduled_by_id)
#  index_verifications_on_escalation_resolved_by_id  (escalation_resolved_by_id)
#  index_verifications_on_guardian_consent_id        (guardian_consent_id)
#  index_verifications_on_knot_id                    (knot_id)
#  index_verifications_on_pre_reviewer_id            (pre_reviewer_id)
#  index_verifications_on_previous_attempt_id        (previous_attempt_id)
#  index_verifications_on_second_verifier_id         (second_verifier_id)
#  index_verifications_on_status                     (status)
#  index_verifications_on_user_id                    (user_id)
#  index_verifications_on_verifier_id                (verifier_id)
#
# Foreign Keys
#
#  fk_rails_...  (call_scheduled_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (escalation_resolved_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (guardian_consent_id => guardian_consents.id) ON DELETE => nullify
#  fk_rails_...  (knot_id => knots.id) ON DELETE => nullify
#  fk_rails_...  (pre_reviewer_id => users.id) ON DELETE => nullify
#  fk_rails_...  (previous_attempt_id => verifications.id) ON DELETE => nullify
#  fk_rails_...  (second_verifier_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verifier_id => users.id) ON DELETE => nullify
#
RSpec.describe Verification do
  it "has a public id" do
    expect(create(:verification).public_id).to start_with("verif_")
  end

  it "has no column for a video or a recording of the call" do
    expect(described_class.column_names.grep(/video|recording|record_url/)).to be_empty
  end

  it "has no column for a value from the ID" do
    expect(described_class.column_names.grep(/number|legal_name|birth|dob|country|gender/)).to be_empty
  end

  describe "validations" do
    it "needs an image for a document call" do
      verification = build(:verification, id_document: nil)

      expect(verification).not_to be_valid
      expect(verification.errors[:id_document]).to be_present
    end

    it "accepts only image and PDF files" do
      verification = build(:verification, id_document: Rack::Test::UploadedFile.new(
        Rails.root.join("spec/fixtures/files/not_an_image.txt"), "text/plain"
      ))

      expect(verification).not_to be_valid
      expect(verification.errors[:id_document]).to be_present
    end

    it "needs a known document type and method" do
      expect(build(:verification, document_type: "library_card")).not_to be_valid
      expect(build(:verification, verification_method: "selfie")).not_to be_valid
    end

    it "needs no image for a digital ID call" do
      expect(build(:verification, verification_method: "digital_id_call", document_type: nil, id_document: nil)).to be_valid
    end
  end

  it "stores the image encrypted" do
    verification = create(:verification)
    plain = Rails.root.join("spec/fixtures/files/id_document.png").binread
    blob = verification.id_document.blob

    stored = blob.service.download(blob.key)

    expect(stored).not_to eq(plain)
    expect(verification.id_document.download).to eq(plain)
  end

  describe "the decision" do
    it "can't change after it is recorded" do
      verification = create(:verification, :verified)

      expect(verification.update(decision_reason: "Changed later")).to be(false)
      expect(verification.errors[:base]).to include("The decision can't change after it is recorded")
    end

    it "needs a written reason" do
      verification = build(:verification, :verified, decision_reason: "")

      expect(verification).not_to be_valid
    end
  end

  describe "#retry_available_at" do
    it "is the decision plus the configured cooldown for a fail" do
      verification = create(:verification, :failed, decided_at: Time.zone.local(2026, 10, 1, 12))

      expect(verification.retry_available_at).to eq(Time.zone.local(2026, 10, 1, 12) + VerificationSettings.failed_call_cooldown)
    end

    it "is nil for any other state" do
      expect(create(:verification, :verified).retry_available_at).to be_nil
    end
  end

  it "lists the chain of attempts, newest first" do
    first = create(:verification, :failed)
    second = create(:verification, :failed, user: first.user, previous_attempt: first)
    third = create(:verification, user: first.user, previous_attempt: second)

    expect(third.chain).to eq([third, second, first])
  end
end
