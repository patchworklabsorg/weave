# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnotLinker do
  include ActiveJob::TestHelper

  let(:verifier) { create(:user, :identity_team) }
  let(:second) { create(:user, :identity_team) }

  def identifiers(**overrides)
    defaults = {
      document_type: "passport",
      issuing_country: "DE",
      document_number: "C01X00T47",
      national_id: nil,
      legal_name: "Erika Mustermann",
      date_of_birth: Date.new(1990, 8, 12)
    }
    VerificationIdentifiers.new(**defaults, **overrides)
  end

  def decide(verification, outcome: "verified", ids: identifiers, **overrides)
    match_account!(verification.user, ids) if outcome == "verified" && ids
    VerificationFlow.decide(verification, by: verifier, outcome:, reason: "Face matched the ID on the call.",
                                          age_consistent: true, region_consistent: true, identifiers: ids, **overrides)
  end

  def pass(user, ids: identifiers, **)
    verification = create(:verification, :call_scheduled, user:)
    result = decide(verification, ids:, **)
    raise "pass failed: #{result.errors}" unless result.success?

    verification.reload
  end

  # A member who passed and then deleted their account.
  def deleted_member_knot(ids: identifiers)
    old = create(:user, :verified)
    pass(old, ids:)
    knot = described_class.write_record_and_detach!(old).knot
    old.destroy!
    knot.reload
  end

  describe "a first pass" do
    let(:member) { create(:user, :verified) }

    it "creates the member's Knot with hashes only and links the attempt" do
      verification = pass(member)
      knot = member.reload.knot

      expect(knot.knot_hashes.pluck(:kind)).to contain_exactly("document", "soft")
      expect(verification.knot).to eq(knot)
      expect(verification.events.pluck(:kind)).to include("knot_linked")
    end

    it "stores no plain identifier anywhere in the Knot tables or the audit rows" do
      verification = pass(member, ids: identifiers(national_id: "12345678901"))
      dump = [Knot.all, KnotHash.all, verification.events].flat_map { |scope| scope.map(&:attributes) }.to_json

      expect(dump).not_to include("C01X00T47", "Mustermann", "12345678901", "1990-08-12")
    end

    it "stores nothing on a fail" do
      verification = create(:verification, :call_scheduled, user: member)

      decide(verification, outcome: "failed")

      expect(Knot.count).to eq(0)
      expect(KnotHash.count).to eq(0)
    end

    it "links the earlier failed attempts of the chain to the Knot" do
      failed = create(:verification, :failed, user: member, decided_at: 30.days.ago)
      verification = create(:verification, :call_scheduled, user: member, previous_attempt: failed)
      decide(verification)

      expect(failed.reload.knot).to eq(member.reload.knot)
    end
  end

  describe "re-verification while the account is live" do
    let(:member) { create(:user, :verified) }

    it "accretes: a new passport adds a hash and the old one stays" do
      pass(member)
      old_digests = member.reload.knot.knot_hashes.pluck(:digest)

      pass(member, ids: identifiers(document_number: "C02NEW999"))
      knot = member.reload.knot

      expect(knot.knot_hashes.where(kind: "document").count).to eq(2)
      expect(knot.knot_hashes.pluck(:digest)).to include(*old_digests)
      expect(Knot.count).to eq(1)
    end

    it "does not route the member's own Knot to review" do
      pass(member)
      verification = create(:verification, :call_scheduled, user: member)

      expect(decide(verification, ids: identifiers(document_number: "C02NEW999"))).to be_success
      expect(verification.reload.knot_review_reason).to be_nil
    end
  end

  describe "a strong match" do
    it "gives a returning member their old Knot: same person, grants and caps carry over" do
      old_knot = deleted_member_knot
      create(:program_grant, knot: old_knot, program: "ganymede")
      newcomer = create(:user, :verified)

      verification = pass(newcomer)

      expect(newcomer.reload.knot).to eq(old_knot)
      expect(KnotGrants.eligibility(newcomer, "ganymede")).to eq(:cap_reached)
      expect(verification.events.find_by(kind: "knot_linked").data).to include("returning" => true, "grants_received" => { "ganymede" => 1 })
    end

    it "matches on a lifelong national ID with a new document" do
      old_knot = deleted_member_knot(ids: identifiers(national_id: "12345678901"))
      newcomer = create(:user, :verified)

      pass(newcomer, ids: identifiers(document_type: "national_id_card", document_number: "L01X00T47",
                                      national_id: "12345678901"))

      expect(newcomer.reload.knot).to eq(old_knot)
    end

    it "links the history of the old account to the new attempt" do
      old_knot = deleted_member_knot
      old_attempt = old_knot.verifications.first
      newcomer = create(:user, :verified)

      pass(newcomer)

      expect(newcomer.reload.knot.verifications).to include(old_attempt)
    end

    it "joins a detached Knot into the member's own Knot and carries the flag" do
      flagged = deleted_member_knot(ids: identifiers(document_number: "OLD111"))
      flagged.update!(blacklisted: true)
      create(:program_grant, knot: flagged)
      member = create(:user, :verified)
      pass(member, ids: identifiers(legal_name: "Erika Neu"))
      own = member.reload.knot

      verification = create(:verification, :call_scheduled, user: member)
      result = decide(verification, ids: identifiers(document_number: "OLD111", legal_name: "Erika Neu"), second_verifier: second)

      expect(result).to be_success
      expect(Knot.exists?(flagged.id)).to be(false)
      expect(own.reload).to be_blacklisted
      expect(own.program_grants.count).to eq(1)
      expect(own.knot_hashes.where(kind: "document").count).to eq(2)
    end

    it "sends a match to a blacklisted Knot to a second verifier, then passes" do
      deleted_member_knot.update!(blacklisted: true)
      newcomer = create(:user, :verified)
      verification = create(:verification, :call_scheduled, user: newcomer)

      first = decide(verification)
      expect(first.errors).to include(:second_verifier)
      expect(verification.reload).to have_attributes(status: "call_scheduled", knot_review_reason: "flagged_match")

      expect(decide(verification, second_verifier: second)).to be_success
      expect(newcomer.reload.knot).to be_blacklisted
    end

    it "rolls the pass back with an error, not a crash, when another account took the document at the same time" do
      newcomer = create(:user, :verified)
      verification = create(:verification, :call_scheduled, user: newcomer)
      # The check before the pass sees no conflict. The other pass lands
      # between the check and the decision.
      allow(described_class).to receive(:pass_errors).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap do
          other = create(:knot)
          document = KnotHasher.digests(identifiers).find(&:strong?)
          other.knot_hashes.create!(kind: document.kind, digest: document.digest)
        end
      end

      result = decide(verification)

      expect(result.errors).to include(:identifiers)
      expect(verification.reload).to be_call_scheduled
      expect(newcomer.reload.knot).to be_nil
    end

    it "stops a pass that matches the Knot of another live account, without a fail" do
      pass(create(:user, :verified))
      newcomer = create(:user, :verified)
      verification = create(:verification, :call_scheduled, user: newcomer)

      result = decide(verification)

      expect(result.errors).to include(:identifiers)
      expect(verification.reload).to be_call_scheduled
      expect(verification.events.pluck(:kind)).to include("knot_duplicate_account")
      expect(newcomer.reload.knot).to be_nil
    end
  end

  describe "a soft-only match" do
    let(:newcomer) { create(:user, :verified) }
    let(:other_document) { identifiers(document_number: "X99NEWDOC") }

    before { deleted_member_knot }

    it "can never fail the member: it only asks for a second verifier" do
      verification = create(:verification, :call_scheduled, user: newcomer)

      result = decide(verification, ids: other_document)

      expect(result.errors.keys).to eq([:second_verifier])
      expect(verification.reload).to have_attributes(status: "call_scheduled", knot_review_reason: "soft_match",
                                                     decided_at: nil, escalated_at: nil)
      expect(newcomer.verifications.failed).to be_empty
      expect(VerificationFlow.excluded_verifier_ids(newcomer)).to be_empty
    end

    it "can never block or flag the member" do
      verification = create(:verification, :call_scheduled, user: newcomer)

      decide(verification, ids: other_document)

      expect(VerificationFlow.submission_blocker(newcomer)).to eq(:in_progress) # the open attempt, nothing else
      expect(Knot.where(blacklisted: true)).to be_empty
      expect(KnotGrants.eligibility(newcomer, "ganymede")).to eq(:not_verified)
    end

    it "passes once a second verifier attends" do
      verification = create(:verification, :call_scheduled, user: newcomer)
      decide(verification, ids: other_document)

      expect(decide(verification, ids: other_document, second_verifier: second)).to be_success
      expect(verification.reload).to be_verified
      expect(newcomer.reload.identity_verified?).to be(true)
      expect(KnotGrants.eligibility(newcomer, "ganymede")).to eq(:eligible)
    end

    it "never links Knots or carries a flag over" do
      Knot.detached.first.update!(blacklisted: true)
      verification = create(:verification, :call_scheduled, user: newcomer)

      decide(verification, ids: other_document, second_verifier: second)

      knot = newcomer.reload.knot
      expect(knot).not_to be_blacklisted
      expect(Knot.count).to eq(2)
      expect(verification.reload.knot_review_reason).to eq("soft_match")
    end

    it "never stops a pass as a duplicate account when the soft match is on a live account" do
      live = create(:user, :verified)
      pass(live, ids: identifiers(document_number: "LIVE0001"), second_verifier: second)
      verification = create(:verification, :call_scheduled, user: newcomer)

      result = decide(verification, ids: other_document)

      expect(result.errors.keys).to eq([:second_verifier])
      expect(verification.events.pluck(:kind)).not_to include("knot_duplicate_account")
      expect(decide(verification, ids: other_document, second_verifier: second)).to be_success
      expect(live.reload.knot).not_to eq(newcomer.reload.knot)
    end

    it "keeps the review on the attempt when the verifier types other identifiers" do
      verification = create(:verification, :call_scheduled, user: newcomer)
      decide(verification, ids: other_document)

      result = decide(verification, ids: identifiers(document_number: "X99NEWDOC", legal_name: "Someone Else"))

      expect(result.errors).to include(:second_verifier)
    end

    it "does not stop the verifier's own fail decision, which is the verifier's judgment" do
      verification = create(:verification, :call_scheduled, user: newcomer)

      expect(decide(verification, outcome: "failed", ids: other_document)).to be_success
      expect(verification.reload.knot_review_reason).to be_nil
    end
  end

  describe ".write_record_and_detach!" do
    it "detaches the Knot and keeps the hashes, the flag and the grants" do
      member = create(:user, :verified)
      pass(member)
      knot = member.reload.knot
      knot.update!(blacklisted: true)
      create(:program_grant, knot:)

      record = described_class.write_record_and_detach!(member)
      member.destroy!

      expect(record).to have_attributes(knot:, blacklisted: true, grants_received: { "ganymede" => 1 })
      knot.reload
      expect(knot).to be_detached
      expect(knot).to be_blacklisted
      expect(knot.knot_hashes.count).to eq(2)
      expect(knot.program_grants.count).to eq(1)
    end

    it "drops the requests that need a live member" do
      member = create(:user, :verified)
      pass(member)
      knot = member.reload.knot
      create(:knot_change_request, knot:, verification: knot.audit_verification, kind: "name_change")
      create(:knot_change_request, knot:, verification: knot.audit_verification, kind: "set_blacklist")

      described_class.write_record_and_detach!(member)

      expect(knot.change_requests.pluck(:kind)).to eq(["set_blacklist"])
    end

    it "returns nil for a member with no Knot" do
      expect(described_class.write_record_and_detach!(create(:user))).to be_nil
    end

    it "keeps the Knot when the user row is deleted without the call" do
      member = create(:user, :verified)
      pass(member)
      knot = member.reload.knot

      member.destroy!

      expect(knot.reload).to be_detached
    end
  end
end
