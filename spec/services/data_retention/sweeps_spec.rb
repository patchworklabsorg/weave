# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataRetention::Sweeps do
  describe ".purge_verification_audit!" do
    def deleted_attempt(deleted_at:, knot: nil)
      verification = create(:verification, :verified, knot:)
      VerificationEvent.record!(verification, :decided)
      verification.update_columns(user_id: nil, account_deleted_at: deleted_at) # rubocop:disable Rails/SkipsModelValidations
      verification
    end

    it "destroys the records 3 years after the account was deleted, with their audit rows" do
      old = deleted_attempt(deleted_at: 3.years.ago - 1.day)
      recent = deleted_attempt(deleted_at: 2.years.ago)
      live = create(:verification, :verified)

      expect(described_class.purge_verification_audit!).to eq(1)

      expect(Verification.exists?(old.id)).to be(false)
      expect(VerificationEvent.where(verification_id: old.id)).not_to exist
      expect(PaperTrail::Version.where(item_type: "Verification", item_id: old.id)).not_to exist
      expect(Verification.exists?(recent.id)).to be(true)
      expect(Verification.exists?(live.id)).to be(true)
    end

    it "holds a blacklisted member's records while the flag stands (the fraud-evidence hold)" do
      knot = create(:knot, :detached, :blacklisted)
      held = deleted_attempt(deleted_at: 4.years.ago, knot:)

      expect(described_class.purge_verification_audit!).to eq(0)
      expect(Verification.exists?(held.id)).to be(true)

      knot.update!(blacklisted: false)
      expect(described_class.purge_verification_audit!).to eq(1)
      expect(Verification.exists?(held.id)).to be(false)
    end

    it "also removes the break-glass records of the attempt" do
      old = deleted_attempt(deleted_at: 4.years.ago)
      record = create(:break_glass_record, verification: old, user: nil)

      described_class.purge_verification_audit!

      expect(BreakGlassRecord.exists?(record.id)).to be(false)
    end
  end

  describe ".anonymize_financial!" do
    it "keeps a disbursement in full for 7 years, then keeps only the amount, the program and the year" do
      old = create(:grant_disbursement, disbursed_on: 7.years.ago.to_date - 1.day)
      recent = create(:grant_disbursement, disbursed_on: 6.years.ago.to_date)

      expect(described_class.anonymize_financial!).to eq(1)

      old.reload
      expect(old.attributes.values_at("user_id", "payee_name_ciphertext", "payee_email_ciphertext", "reference_ciphertext")).to all(be_nil)
      expect(old).to have_attributes(amount_cents: 50_000, program: "ganymede",
                                     disbursed_on: (7.years.ago.to_date - 1.day).beginning_of_year,
                                     created_at: old.created_at.beginning_of_year)
      expect(old).to be_anonymized
      expect(recent.reload.payee_name).to eq("Ada Lovelace")
    end

    it "keeps it longer when the funder's terms say so" do
      funded = create(:grant_disbursement, funder: "test_funder", disbursed_on: 8.years.ago.to_date)

      expect(described_class.anonymize_financial!).to eq(0)
      expect(funded.reload.payee_name).to eq("Ada Lovelace")

      travel_to(3.years.from_now) { described_class.anonymize_financial! }
      expect(funded.reload).to be_anonymized
    end
  end

  describe ".fold_expired_funder_records!" do
    it "folds a retained record into the aggregates when the funder's window closes" do
      expired = create(:program_participation, :funder_required, user: nil, retained_until: 1.day.ago, year: 2024,
                                                                 age_band: "16-17", region: "US", amount_band: "none")
      waiting = create(:program_participation, :funder_required, user: nil, retained_until: 1.day.from_now)

      expect(described_class.fold_expired_funder_records!).to eq(1)

      expect(ProgramParticipation.exists?(expired.id)).to be(false)
      expect(ProgramParticipation.exists?(waiting.id)).to be(true)
      expect(DeleteTimeAggregate.sole.attributes).to include("year" => 2024, "age_band" => "16-17", "region" => "US",
                                                             "count" => 1)
    end
  end

  describe ".purge_adult_guardian_contacts!" do
    it "deletes the guardian contact once the member turns 18" do
      adult = create(:guardian_consent, :granted)
      adult.user.update_columns(birthday: 18.years.ago.to_date - 1.day) # rubocop:disable Rails/SkipsModelValidations
      minor = create(:guardian_consent, :granted)

      expect(described_class.purge_adult_guardian_contacts!).to eq(1)
      expect(GuardianConsent.exists?(adult.id)).to be(false)
      expect(GuardianConsent.exists?(minor.id)).to be(true)
    end
  end

  describe ".expire_takeouts!" do
    it "deletes the file after the download window" do
      takeout = create(:takeout_request, status: "ready", expires_at: 1.minute.ago)
      takeout.archive.attach(io: StringIO.new("{}"), filename: "x.json", content_type: "application/json")

      expect(described_class.expire_takeouts!).to eq(1)
      expect(takeout.reload.status).to eq("expired")
      expect(takeout.archive).not_to be_attached
    end
  end

  describe ".purge_webhook_deliveries!" do
    it "removes delivery logs older than the window" do
      webhook = create(:service_webhook, event_type: "user.deleted")
      old = travel_to(31.days.ago) { WebhookDispatcher.ping(webhook) }
      recent = WebhookDispatcher.ping(webhook)

      expect(described_class.purge_webhook_deliveries!).to eq(1)
      expect(WebhookDelivery.all).to contain_exactly(recent)
      expect(WebhookDelivery.exists?(old.id)).to be(false)
    end
  end

  it "runs every sweep from the daily job" do
    expect(described_class).to receive(:run_all).and_call_original

    DataRetentionJob.perform_now
  end
end
