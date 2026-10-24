# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeVerificationDocumentsJob do
  def run = described_class.perform_now

  it "purges the image a configured number of days after a pass, and keeps the record" do
    old = create(:verification, :verified, decided_at: VerificationSettings.purge_image_after_pass.ago - 1.hour)
    recent = create(:verification, :verified, decided_at: 1.hour.ago)

    run

    expect(old.reload.id_document).not_to be_attached
    expect(old.document_purged_at).to be_present
    expect(old.events.find_by!(kind: "document_purged").data).to eq("reason" => "after_pass")
    expect(recent.reload.id_document).to be_attached
  end

  it "purges the image of a closed attempt after its window" do
    failed = create(:verification, :failed, decided_at: VerificationSettings.purge_image_after_close.ago - 1.hour)
    rejected = create(:verification, status: "needs_resubmission", resubmission_note: "Blurry",
                                     pre_reviewed_at: VerificationSettings.purge_image_after_close.ago - 1.hour)

    run

    expect(failed.reload.id_document).not_to be_attached
    expect(rejected.reload.id_document).not_to be_attached
  end

  it "keeps the image while the lead reviews an escalation" do
    escalated = create(:verification, :failed, escalated_at: 1.hour.ago,
                                               decided_at: VerificationSettings.purge_image_after_close.ago - 1.hour)

    run

    expect(escalated.reload.id_document).to be_attached
  end

  it "keeps the image of an attempt in progress" do
    open = create(:verification, :call_scheduled, created_at: 1.year.ago)

    run

    expect(open.reload.id_document).to be_attached
  end

  it "purges at once when the account is deleted" do
    verification = create(:verification)
    verification.update_columns(user_id: nil) # rubocop:disable Rails/SkipsModelValidations

    run

    expect(verification.reload.id_document).not_to be_attached
  end

  it "does nothing new the second time" do
    create(:verification, :verified, decided_at: 1.year.ago)
    run

    expect { run }.not_to change(VerificationEvent, :count)
  end
end
