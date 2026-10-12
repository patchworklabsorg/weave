# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeGuardianConsentsJob do
  it "deletes consents past their retention period and keeps the others" do
    current = create(:guardian_consent, :granted)
    old = create(:guardian_consent, :granted, account_deleted_at: 13.months.ago)

    described_class.perform_now

    expect(GuardianConsent.all).to contain_exactly(current)
    expect(GuardianConsent.exists?(old.id)).to be(false)
  end

  it "deletes the versions that hold copies of the guardian fields" do
    old = create(:guardian_consent, :granted)
    old.update!(note: "called the guardian")
    old.update_columns(account_deleted_at: 13.months.ago) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now

    expect(PaperTrail::Version.where(item_type: "GuardianConsent", item_id: old.id)).to be_empty
  end

  it "does nothing on a second run" do
    create(:guardian_consent, expires_at: 31.days.ago)
    described_class.perform_now

    expect { described_class.perform_now }.not_to change(GuardianConsent, :count)
  end
end
