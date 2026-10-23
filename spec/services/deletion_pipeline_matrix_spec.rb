# frozen_string_literal: true

require "rails_helper"

# The v0.8 retention matrix is the acceptance criteria of the deletion
# pipeline: one example per category of DataCategories.
RSpec.describe DeletionPipeline, "retention matrix" do # rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
  let(:user) { create(:user, :verified, birthday: Date.new(2008, 5, 1)) }
  let(:request) { create(:deletion_request, :approved, user:) }

  def run! = described_class.run!(request.reload).tap { |r| raise r.error if r.error }

  it "covers exactly the nine categories of the matrix" do
    expect(DataCategories::KEYS).to eq(%w[raw_id_images account_profile guardian_contact demographics
                                          verification_audit financial participation funder_records knot])
    expect(DataCategories.all.to_h { |category| [category.key, category.outcome] }).to eq(
      "raw_id_images" => "deleted", "account_profile" => "deleted", "guardian_contact" => "deleted",
      "demographics" => "folded", "verification_audit" => "retained", "financial" => "retained",
      "participation" => "folded", "funder_records" => "retained", "knot" => "retained"
    )
  end

  it "raw ID images: deleted (a stored image goes at once)" do
    verification = create(:verification, :verified, user:)
    expect(verification.id_document).to be_attached

    expect { run! }.to have_enqueued_job(ActiveStorage::PurgeJob)
    expect(verification.reload.document_purged_at).to be_present
    expect(verification.events.where(kind: "document_purged").pick(:data)).to eq("reason" => "account_deleted")
  end

  it "account and profile: deleted for real, with its PaperTrail rows" do
    user.update!(pronouns: "she/her")
    address_id = user.email_addresses.first.id
    expect(PaperTrail::Version.where(item_type: "User", item_id: user.id)).to exist

    run!

    expect(User.exists?(user.id)).to be(false)
    expect(EmailAddress.exists?(address_id)).to be(false)
    expect(PaperTrail::Version.where(item_type: "User", item_id: user.id)).not_to exist
    expect(PaperTrail::Version.where(item_type: "EmailAddress", item_id: address_id)).not_to exist
    expect(PaperTrail::Version.where(event: "destroy", item_type: "User")).not_to exist
  end

  it "guardian contact: deleted, not kept after the account goes" do
    consent = create(:guardian_consent, :granted, user:)

    run!

    expect(GuardianConsent.exists?(consent.id)).to be(false)
    expect(PaperTrail::Version.where(item_type: "GuardianConsent", item_id: consent.id)).not_to exist
  end

  it "demographics vault record: banded into the departed totals, then deleted" do
    DemographicsVault.record(user, { "gender_identity" => "woman" }, consent: true)
    create(:program_participation, user:, year: 2026)

    run!

    expect(DemographicRecord.where(user_id: user.id)).not_to exist
    fold = DemographicFold.sole
    expect(fold.cohorts).to contain_exactly(Date.current.year.to_s, "ganymede-2026")
    expect(fold.attributes.keys).not_to include("user_id")
  end

  it "verification audit records: retained, without the account link, with the window started" do
    verification = create(:verification, :verified, user:)

    run!

    verification.reload
    expect(verification.user_id).to be_nil
    expect(verification.account_deleted_at).to be_present
    expect(verification.events.where.not(user_id: nil)).not_to exist
    expect(request.reload.receipt["retained"]).to include("verification_audit")
  end

  it "financial / grant disbursement: retained under its obligation, detached from the account" do
    disbursement = create(:grant_disbursement, user:)

    run!

    disbursement.reload
    expect(disbursement.user_id).to be_nil
    expect(disbursement.detached_at).to be_present
    expect(disbursement.payee_name).to eq("Ada Lovelace")
    expect(disbursement.amount_cents).to eq(50_000)
    expect(request.reload.receipt["retained"]).to include("financial")
  end

  it "participation data: folded into the delete-time aggregates, then destroyed" do
    participation = create(:program_participation, user:, year: 2026, outcome: "completed")
    UserAddress.create!(addressable: user, address_type: "Shipping", line1: "1 Main St", city: "Springfield",
                        state: "IL", postal_code: "62701", country: "us")
    user.reload

    run!

    expect(ProgramParticipation.exists?(participation.id)).to be(false)
    cell = DeleteTimeAggregate.sole
    expect(cell.attributes.except("id")).to include("program" => "ganymede", "year" => 2026, "outcome" => "completed",
                                                    "age_band" => "18-24", "region" => "US", "amount_band" => "none",
                                                    "count" => 1)
    expect(DeleteTimeAggregate.column_names).not_to include("user_id", "created_at")
  end

  it "funder-required individual records: retained for the funder's window, not folded yet" do
    participation = create(:program_participation, :funder_required, user:, year: 2026)

    travel_to(Time.zone.local(2026, 11, 1)) { run! }

    participation.reload
    expect(participation.user_id).to be_nil
    expect(participation.retained_until).to eq(Time.zone.local(2028, 11, 1))
    expect(participation.age_band).to eq("18-24")
    expect(DeleteTimeAggregate.count).to eq(0)
    expect(request.reload.receipt["retained"]).to include("funder_records")
  end

  it "the Knot and its record: retained, detached, with the flag and the grants" do
    knot = create(:knot, user:, blacklisted: true)
    create(:program_grant, knot:)
    create(:knot_hash, knot:)

    run!

    knot.reload
    expect(knot.user_id).to be_nil
    expect(knot.blacklisted).to be(true)
    expect(knot.program_grants.count).to eq(1)
    expect(knot.knot_hashes.count).to eq(1)
    expect(request.reload.receipt["retained"]).to include("knot")
  end
end
