# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletionPipeline do
  include ActionMailer::TestHelper

  let(:user) { create(:user, :verified, email: "leaving@example.com") }
  let(:request) { create(:deletion_request, :approved, user:) }

  before do
    create(:program_participation, user:)
    create(:knot, user:)
    DemographicsVault.record(user, { "gender_identity" => "woman" })
  end

  it "runs exactly the four steps, in order" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    calls = []
    allow(DeleteTimeAggregates).to receive(:add!).and_wrap_original do |m, *a|
      calls << :fold
      m.call(*a)
    end
    allow(KnotLinker).to receive(:write_record_and_detach!).and_wrap_original do |m, *a|
      calls << :knot
      expect(DeleteTimeAggregate.count).to eq(1) # the fold came first
      expect(User.exists?(user.id)).to be(true) # the identity is still intact
      m.call(*a)
    end
    allow(DataHandlingMailer).to receive(:deletion_receipt).and_wrap_original do |m, *a|
      calls << :receipt
      expect(User.exists?(user.id)).to be(false) # severed before the receipt
      m.call(*a)
    end

    result = described_class.run!(request)

    expect(result).to be_success
    expect(calls).to eq(%i[fold knot receipt])
    run = request.runs.sole
    expect(run.step_names).to eq(described_class::STEPS)
    expect(described_class::STEPS).to eq(%w[fold_aggregates write_knot_record sever_identity send_receipt])
    expect(run.steps.pluck("status")).to all(eq("done"))
    expect(run.outcome).to eq("completed")
    expect(request.reload).to be_completed
  end

  it "leaves the identity intact when a step before step 3 fails" do # rubocop:disable RSpec/MultipleExpectations
    allow(KnotLinker).to receive(:write_record_and_detach!).and_raise(RuntimeError, "boom")

    result = described_class.run!(request)

    expect(result).not_to be_success
    expect(User.exists?(user.id)).to be(true)
    expect(user.reload.knot).to be_present
    expect(DemographicRecord.where(user_id: user.id)).to exist
    expect(DemographicFold.count).to eq(0)
    expect(DeleteTimeAggregate.count).to eq(0) # the fold rolled back
    expect(ProgramParticipation.where(user_id: user.id)).to exist
    expect(request.reload).to be_failed
    run = request.runs.sole
    expect(run.outcome).to eq("failed")
    expect(run.error_class).to eq("RuntimeError")
    expect(run.steps.map { |step| step.values_at("step", "status") }).to eq([%w[fold_aggregates rolled_back],
                                                                             %w[write_knot_record failed]])
  end

  it "leaves the identity intact when step 3 fails part of the way" do
    allow_any_instance_of(User).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed) # rubocop:disable RSpec/AnyInstance

    described_class.run!(request)

    expect(User.exists?(user.id)).to be(true)
    expect(Knot.find_by(user_id: user.id)).to be_present
    expect(request.reload).to be_failed
  end

  it "sends the receipt and then forgets the address" do # rubocop:disable RSpec/MultipleExpectations
    expect { described_class.run!(request) }.to change { ActionMailer::Base.deliveries.size }.by(1)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(["leaving@example.com"])
    expect(mail.body.encoded).to include("Account and profile", "The Knot", Weave.data_page_url)
    expect(request.reload.receipt_email).to be_nil
    expect(request.receipt_sent_at).to be_present
    expect(request.user_id).to be_nil
    expect(Ahoy::Message.count).to eq(0)
  end

  it "only sends the receipt again on a retry after a failed step 4" do
    allow(DataHandlingMailer).to receive(:deletion_receipt).and_raise(Net::SMTPFatalError.new("down"))
    described_class.run!(request)
    expect(User.exists?(user.id)).to be(false)
    expect(request.reload).to be_failed

    allow(DataHandlingMailer).to receive(:deletion_receipt).and_call_original
    result = described_class.run!(request.reload)

    expect(result).to be_success
    expect(request.runs.last.steps.pluck("status")).to eq(%w[done_earlier done_earlier done_earlier done])
    expect(DeleteTimeAggregate.sum(:count)).to eq(1) # not folded twice
  end

  it "refuses a request that nobody approved" do
    pending_request = create(:deletion_request, user: create(:user, :verified))

    expect { described_class.run!(pending_request) }.to raise_error(described_class::NotRunnable)
    expect(pending_request.runs).to be_empty
  end

  it "keeps no per-member archive row anywhere" do
    described_class.run!(request)

    request.reload
    expect(request.attributes.values_at("user_id", "receipt_email_ciphertext")).to all(be_nil)
    expect(request.receipt.to_json).not_to include("leaving@example.com", user.p_id, user.first_name)
    expect(ActiveRecord::Base.connection.tables.grep(/archive|capsule/)).to be_empty
  end

  it "clears the user from PaperTrail rows they authored" do
    PaperTrail.request(whodunnit: user.id.to_s) { create(:group).update!(name: "Renamed") }

    described_class.run!(request)

    expect(PaperTrail::Version.where(whodunnit: user.id.to_s)).not_to exist
  end

  it "scrubs the PaperTrail rows of records the member deleted earlier" do
    old_address = create(:email_address, user:, email: "old-address@example.com")
    old_address.destroy!
    other_user = create(:user)
    other_address = create(:email_address, user: other_user, email: "stays@example.com")
    other_address.destroy!
    expect(PaperTrail::Version.where(item_type: "EmailAddress", item_id: old_address.id, event: "destroy")).to exist

    described_class.run!(request)

    expect(PaperTrail::Version.where(item_type: "EmailAddress", item_id: old_address.id)).not_to exist
    expect(PaperTrail::Version.where("object LIKE ?", "%old-address@example.com%")).not_to exist
    expect(PaperTrail::Version.where(item_type: "EmailAddress", item_id: other_address.id, event: "destroy")).to exist
  end

  it "deletes the member's passkeys and their PaperTrail rows" do
    kept = register_passkey(user, nickname: "Laptop")
    removed = register_passkey(user, nickname: "Old phone")
    removed.destroy!
    expect(PaperTrail::Version.where(item_type: "User::Passkey", item_id: removed.id, event: "destroy")).to exist

    described_class.run!(request)

    expect(User::Passkey.where(id: [kept.id, removed.id])).not_to exist
    expect(PaperTrail::Version.where(item_type: "User::Passkey", item_id: [kept.id, removed.id])).not_to exist
  end

  it "deletes the member's social profiles and their PaperTrail rows" do
    removed = user.social_profiles.create!(provider: "github", uid: "1", username: "old-account")
    removed.destroy!
    expect(PaperTrail::Version.where(item_type: "SocialProfile", item_id: removed.id, event: "destroy")).to exist
    kept = user.social_profiles.create!(provider: "github", uid: "583231", username: "octocat")

    described_class.run!(request)

    expect(SocialProfile.where(id: [kept.id, removed.id])).not_to exist
    expect(PaperTrail::Version.where(item_type: "SocialProfile", item_id: [kept.id, removed.id])).not_to exist
  end

  it "deletes Ahoy events of the member on a visit that is not theirs" do
    visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid, started_at: Time.current)
    event = Ahoy::Event.create!(visit:, user:, name: "signed_in", time: Time.current)

    described_class.run!(request)

    expect(Ahoy::Event.exists?(event.id)).to be(false)
  end

  it "empties the address on earlier requests of the member" do
    old_request = create(:deletion_request, user:)
    old_request.update!(review_note: "Could not confirm.", reviewed_by: create(:user, :identity_team))
    old_request.reject!
    expect(old_request.reload.receipt_email).to be_present
    request # The new request, made after the old one closed.

    described_class.run!(request)

    expect(old_request.reload.receipt_email_ciphertext).to be_nil
  end

  it "keeps only the first line of an error in the run log" do
    error = ActiveRecord::InvalidForeignKey.new("PG::ForeignKeyViolation: ERROR: violates\nDETAIL: Key (email)=(leaving@example.com)")
    allow(KnotLinker).to receive(:write_record_and_detach!).and_raise(error)

    described_class.run!(request)

    expect(request.runs.sole.error_message).to eq("PG::ForeignKeyViolation: ERROR: violates")
  end
end
