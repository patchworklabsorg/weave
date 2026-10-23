# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdentityGovernance do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, :owner, :verified, is_board: true, first_name: "Jasper") }
  let(:board_member) { create(:user, :verified, is_board: true, first_name: "Kieran") }
  let(:other_board_member) { create(:user, :verified, is_board: true, first_name: "Dominic") }

  # A person who meets every verifier precondition.
  def ready_candidate(**attributes)
    user = create(:user, :verified, **attributes)
    create(:verification, :verified, user:)
    user
  end

  def propose(kind, subject, by: owner, reason: "Needed for the calls.")
    result = described_class.propose(kind:, subject:, by:, reason:)
    expect(result).to be_success, result.message
    result.record
  end

  describe "adding a verifier" do
    let(:candidate) { ready_candidate }

    it "needs an owner to propose and a different board member to approve" do
      proposal = propose("add_member", candidate)

      expect(candidate.reload.identity_team).to be(false)
      expect(described_class.approve(proposal, by: board_member)).to be_success
      expect(candidate.reload.identity_team).to be(true)
      expect(proposal.reload).to be_applied
    end

    it "does not let a non-owner propose, not even a board member or a superadmin" do
      [board_member, create(:user, :superadmin, :verified)].each do |actor|
        result = described_class.propose(kind: "add_member", subject: candidate, by: actor, reason: "Why not.")
        expect(result).not_to be_success
      end
      expect(IdentityGovernanceProposal.count).to eq(0)
    end

    it "needs a reason" do
      result = described_class.propose(kind: "add_member", subject: candidate, by: owner, reason: " ")

      expect(result.errors).to include(reason: "is required")
    end

    it "does not let the proposer approve their own proposal, even as a board member" do
      proposal = propose("add_member", candidate)

      expect(described_class.approve(proposal, by: owner)).not_to be_success
      expect(candidate.reload.identity_team).to be(false)
    end

    it "does not let the subject approve a proposal about themselves" do
      candidate.update!(is_board: true)
      proposal = propose("add_member", candidate)

      expect(described_class.approve(proposal, by: candidate)).not_to be_success
      expect(candidate.reload.identity_team).to be(false)
    end

    it "does not let someone who is not on the board approve" do
      proposal = propose("add_member", candidate)

      expect(described_class.approve(proposal, by: create(:user, :owner, :verified))).not_to be_success
    end

    it "refuses a proposal for someone already on the team, or a second open proposal" do
      propose("add_member", candidate)

      expect(described_class.propose(kind: "add_member", subject: candidate, by: owner, reason: "Again.")).not_to be_success
      expect(described_class.propose(kind: "add_member", subject: create(:user, :identity_team), by: owner, reason: "x"))
        .not_to be_success
    end

    describe "preconditions at the approval" do
      it "refuses a candidate who is not verified" do
        candidate = create(:user, :verified)
        proposal = propose("add_member", candidate)

        result = described_class.approve(proposal, by: board_member)

        expect(result.message).to include("Not verified")
        expect(candidate.reload.identity_team).to be(false)
        expect(proposal.reload).to be_pending
        expect(proposal.approvals).to be_empty
      end

      it "refuses a candidate under 18" do
        candidate = ready_candidate(birthday: 17.years.ago.to_date)
        proposal = propose("add_member", candidate)

        expect(described_class.approve(proposal, by: board_member).message).to include("17 years old")
        expect(candidate.reload.identity_team).to be(false)
      end

      it "does not check an NDA: NDAs are signed outside Weave" do
        expect(described_class::PRECONDITION_KEYS.values).to eq(%i[verified adult])
        expect(described_class.approve(propose("add_member", candidate), by: board_member)).to be_success
      end

      it "checks at the approval, not at the proposal" do
        candidate = create(:user, :verified)
        proposal = propose("add_member", candidate)
        expect(described_class.approve(proposal, by: board_member)).not_to be_success

        create(:verification, :verified, user: candidate)

        expect(described_class.approve(proposal, by: board_member)).to be_success
        expect(candidate.reload.identity_team).to be(true)
      end

      it "shows each precondition with its state" do
        candidate = create(:user, :verified, birthday: 20.years.ago.to_date)

        checks = described_class.preconditions(candidate).to_h { |check| [check.key, check.met] }

        expect(checks).to eq(verified: false, adult: true)
      end

      it "needs the verification to be decided by another person" do
        candidate = ready_candidate
        candidate.latest_verification.update_columns(verifier_id: candidate.id) # rubocop:disable Rails/SkipsModelValidations

        expect(described_class.preconditions(candidate).find { |check| check.key == :verified }.met).to be(false)
      end

      it "uses the minimum age from the config" do
        candidate = ready_candidate(birthday: 19.years.ago.to_date)
        allow(IdentityGovernanceSettings).to receive(:verifier_minimum_age).and_return(21)

        expect(described_class.preconditions_met?(candidate)).to be(false)
      end
    end

    it "emails the board members who may approve, not the proposer" do
      board_member
      other_board_member

      expect { propose("add_member", candidate) }
        .to have_enqueued_mail(IdentityGovernanceMailer, :approval_needed).twice
    end

    it "logs each step and keeps a role row that names the approver and the proposal" do
      proposal = propose("add_member", candidate)
      described_class.approve(proposal, by: board_member)

      expect(proposal.events.order(:id).pluck(:kind)).to eq(%w[proposed approved applied])
      expect(proposal.events.find_by(kind: "proposed").data).to include("reason" => "Needed for the calls.")
      row = UserRole.active.for_role("verifier").find_by!(user: candidate)
      expect(row).to have_attributes(granted_by: board_member, identity_governance_proposal: proposal, reason: "Needed for the calls.")
      expect(PrivilegedAttributeChange.find_by!(user_role_id: row.id)).to have_attributes(actor_id: board_member.id, operation: "grant")
    end
  end

  describe "expiry" do
    let(:candidate) { ready_candidate }

    it "refuses to approve an expired proposal and marks it expired" do
      proposal = propose("add_member", candidate)

      travel_to(IdentityGovernanceSettings.proposal_expiry.from_now + 1.minute) do
        result = described_class.approve(proposal, by: board_member)
        expect(result.message).to include("expired")
      end
      expect(proposal.reload).to be_expired
      expect(candidate.reload.identity_team).to be(false)
      expect(proposal.events.pluck(:kind)).to include("expired")
    end

    it "expires due proposals in the job" do
      proposal = propose("add_member", candidate)

      travel_to(15.days.from_now) { ExpireIdentityGovernanceProposalsJob.perform_now }

      expect(proposal.reload).to be_expired
    end

    it "lets a new proposal replace an expired one" do
      proposal = propose("add_member", candidate)
      proposal.update!(expires_at: 1.minute.ago)

      expect(described_class.propose(kind: "add_member", subject: candidate, by: owner, reason: "Again.")).to be_success
    end
  end

  describe "rejecting and withdrawing" do
    let(:candidate) { ready_candidate }

    it "lets an eligible board member reject with a reason" do
      proposal = propose("add_member", candidate)

      expect(described_class.reject(proposal, by: board_member, reason: "")).not_to be_success
      expect(described_class.reject(proposal, by: board_member, reason: "Not now.")).to be_success
      expect(proposal.reload).to be_rejected
      expect(described_class.approve(proposal, by: other_board_member)).not_to be_success
    end

    it "lets the proposer withdraw" do
      proposal = propose("add_member", candidate)

      expect(described_class.withdraw(proposal, by: board_member)).not_to be_success
      expect(described_class.withdraw(proposal, by: owner)).to be_success
      expect(proposal.reload).to be_withdrawn
    end
  end

  # A team member verified by another verifier: a new lead or key holder must
  # be one.
  def verified_member(*traits)
    create(:user, :identity_team, *traits).tap { |user| create(:verification, :verified, user:) }
  end

  describe "lead changes" do
    let(:member) { verified_member }

    it "refuses a lead who is not verified, at the proposal and at the approval" do
      unverified = create(:user, :identity_team)
      result = described_class.propose(kind: "set_lead", subject: unverified, by: owner, reason: "x")
      expect(result.message).to include("must be verified")

      proposal = propose("set_lead", member)
      member.latest_verification.update!(reverification_required_at: Time.current, reverification_reason: "birthday_changed")
      expect(described_class.approve(proposal, by: board_member).message).to include("must be verified")
      expect(member.reload.identity_lead).to be(false)
    end

    it "needs an owner to propose and a different board member to approve" do
      proposal = propose("set_lead", member)

      expect(described_class.approve(proposal, by: owner)).not_to be_success
      expect(described_class.approve(proposal, by: board_member)).to be_success
      expect(member.reload.identity_lead).to be(true)

      clear = propose("clear_lead", member)
      described_class.approve(clear, by: board_member)
      expect(member.reload.identity_lead).to be(false)
    end

    it "refuses a lead who is not on the team" do
      result = described_class.propose(kind: "set_lead", subject: create(:user, :verified), by: owner, reason: "x")

      expect(result.message).to include("must be on the identity team first")
    end
  end

  describe "key holder changes" do
    let(:member) { verified_member }

    it "refuses a key holder who is not verified" do
      result = described_class.propose(kind: "add_key_holder", subject: create(:user, :identity_team), by: owner, reason: "x")

      expect(result.message).to include("must be verified")
    end

    before do
      owner
      board_member
      other_board_member
    end

    it "needs every board member at proposal time, and applies only after the last approval" do
      proposal = propose("add_key_holder", member)
      expect(proposal.required_approver_ids).to contain_exactly(owner.id, board_member.id, other_board_member.id)

      described_class.approve(proposal, by: board_member)
      described_class.approve(proposal, by: other_board_member)
      expect(member.reload.identity_key_holder).to be(false)
      expect(proposal.reload).to be_pending

      expect(described_class.approve(proposal, by: owner)).to be_success
      expect(member.reload.identity_key_holder).to be(true)
      expect(proposal.reload.approvals.count).to eq(3)
    end

    it "uses the board as it was at proposal time" do
      proposal = propose("add_key_holder", member)
      newcomer = create(:user, :verified, is_board: true)

      expect(described_class.approve(proposal, by: newcomer)).not_to be_success
      [owner, board_member, other_board_member].each { |approver| described_class.approve(proposal, by: approver) }
      expect(member.reload.identity_key_holder).to be(true)
    end

    it "does not count one approval twice" do
      proposal = propose("add_key_holder", member)

      described_class.approve(proposal, by: board_member)

      expect(described_class.approve(proposal, by: board_member)).not_to be_success
      expect(proposal.approvals.count).to eq(1)
    end

    it "refuses a board member who left the board" do
      proposal = propose("add_key_holder", member)
      board_member.update!(is_board: false)

      expect(described_class.approve(proposal, by: board_member)).not_to be_success
    end

    it "sends key_holders_changed after the commit when a holder is added or removed" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe(described_class::KEY_HOLDERS_CHANGED) { |*, payload| events << payload }
      add = propose("add_key_holder", member)
      [owner, board_member].each { |approver| described_class.approve(add, by: approver) }
      expect(events).to be_empty
      described_class.approve(add, by: other_board_member)

      remove = propose("remove_key_holder", member.reload)
      [owner, board_member, other_board_member].each { |approver| described_class.approve(remove, by: approver) }

      expect(events.map { |payload| [payload[:user], payload[:change]] }).to eq([[member, :added], [member, :removed]])
      expect(events.first[:holder_ids]).to include(member.id)
      expect(events.last[:holder_ids]).not_to include(member.id)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "refuses a key holder over the limit" do
      create_list(:user, VerificationSettings.max_key_holders, :key_holder)

      result = described_class.propose(kind: "add_key_holder", subject: member, by: owner, reason: "x")

      expect(result.message).to include("already #{VerificationSettings.max_key_holders} key holders")
    end

    it "refuses a key holder who is not on the team" do
      result = described_class.propose(kind: "add_key_holder", subject: create(:user, :verified), by: owner, reason: "x")

      expect(result).not_to be_success
    end

    it "refuses a key holder change when the owner is the only board member, so nobody approves it alone" do
      board_member.update!(is_board: false)
      other_board_member.update!(is_board: false)

      result = described_class.propose(kind: "add_key_holder", subject: member, by: owner, reason: "x")

      expect(result.message).to include("at least 2 board members")
      expect(IdentityGovernanceProposal.count).to eq(0)
    end

    it "needs a second person even when the proposer is on the board" do
      other_board_member.update!(is_board: false)
      proposal = propose("add_key_holder", member)

      expect(described_class.approve(proposal, by: owner)).to be_success
      expect(member.reload.identity_key_holder).to be(false)
      expect(described_class.approve(proposal, by: board_member)).to be_success
      expect(member.reload.identity_key_holder).to be(true)
    end
  end

  describe "removal" do
    let(:member) { create(:user, :key_holder, identity_lead: true) }

    before do
      board_member
      other_board_member
    end

    it "is immediate by one owner, clears every flag, logs it and tells the board" do
      result = nil
      expect { result = described_class.remove_member(member, by: owner, reason: "Left the org.") }
        .to have_enqueued_mail(IdentityGovernanceMailer, :member_removed).exactly(3).times

      expect(result).to be_success
      expect(member.reload).to have_attributes(identity_team: false, identity_key_holder: false, identity_lead: false)
      event = IdentityGovernanceEvent.find_by(kind: "member_removed")
      expect(event).to have_attributes(actor: owner, subject: member)
      expect(event.data).to include("reason" => "Left the org.", "was_key_holder" => true, "was_lead" => true)
    end

    it "lets an identity team lead remove a member, without the admin role" do
      lead = create(:user, :verified, identity_team: true, identity_lead: true)
      plain = create(:user, :identity_team)

      expect(described_class.remove_member(plain, by: lead, reason: "Broke the NDA.")).to be_success
      expect(plain.reload.identity_team).to be(false)
    end

    it "does not let a plain verifier, an admin or a board member remove" do
      [create(:user, :identity_team), create(:user, :superadmin, :verified), board_member].each do |actor|
        expect(described_class.remove_member(member, by: actor, reason: "x")).not_to be_success
      end
      expect(member.reload.identity_team).to be(true)
    end

    it "needs a reason" do
      expect(described_class.remove_member(member, by: owner, reason: "")).not_to be_success
    end

    it "sends key_holders_changed for a key holder" do
      payloads = []
      subscriber = ActiveSupport::Notifications.subscribe(described_class::KEY_HOLDERS_CHANGED) { |*, payload| payloads << payload }

      described_class.remove_member(member, by: owner, reason: "Lost both keys.")

      expect(payloads.map { |payload| payload[:change] }).to eq([:removed])
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "cancels the open proposals about the member" do
      proposal = propose("remove_key_holder", member)

      described_class.remove_member(member, by: owner, reason: "Left.")

      expect(proposal.reload).to be_cancelled
    end

    it "takes the member out of the identity-team system group" do
      expect(member.groups.pluck(:slug)).to include("identity-team")

      described_class.remove_member(member, by: owner, reason: "Left.")

      expect(member.reload.groups.pluck(:slug)).not_to include("identity-team")
    end
  end

  describe "bootstrap" do
    let!(:circle) { %w[Jasper Kieran Adam].map { |name| create(:user, :verified, first_name: name) } }

    def jasper = circle[0]
    def kieran = circle[1]
    def adam = circle[2]

    it "adds the first verifiers at once and plans a circle of verification" do
      result = described_class.bootstrap!(circle, by: owner)

      expect(result).to be_success
      expect(circle.map { |user| user.reload.identity_team }).to all(be(true))
      expect(result.record.map { |user, verifier| [user, verifier] }).to eq([[jasper, adam], [kieran, jasper], [adam, kieran]])
      expect(IdentityGovernanceEvent.where(kind: "bootstrap_member_added").count).to eq(3)
    end

    it "lets them verify each other in the circle, each by a different person, and then closes" do
      described_class.bootstrap!(circle, by: owner)
      described_class.bootstrap_status.each do |row|
        create(:verification, :verified, user: row[:user], verifier: row[:verifier])
      end

      expect(circle.map { |user| described_class.preconditions_met?(user.reload) }).to all(be(true))
      expect(described_class.bootstrap_status.map { |row| row[:verified_by] }).to eq([adam, jasper, kieran])
      expect(described_class.bootstrap_open?).to be(false)
    end

    it "refuses to run once any identity team member is verified" do
      verified_member = create(:user, :identity_team)
      create(:verification, :verified, user: verified_member)

      result = described_class.bootstrap!(circle, by: owner)

      expect(result.message).to include("closed")
      expect(jasper.reload.identity_team).to be(false)
    end

    it "runs while team members exist but none is verified" do
      create(:user, :identity_team)

      expect(described_class.bootstrap!(circle, by: owner)).to be_success
    end

    it "needs an owner" do
      expect(described_class.bootstrap!(circle, by: board_member)).not_to be_success
    end

    it "refuses after its first run, even while nobody is verified" do
      described_class.bootstrap!(circle, by: owner)
      later = %w[Mo Lu].map { |name| create(:user, :verified, first_name: name) }

      result = described_class.bootstrap!(later, by: owner)

      expect(result.message).to include("ran before")
      expect(described_class.bootstrap_open?).to be(false)
      expect(later.map { |user| user.reload.identity_team }).to all(be(false))
    end

    describe "the circle in VerificationFlow" do
      # Different identifiers for each person, so the Knot sees no duplicate.
      def identifiers(user)
        VerificationIdentifiers.new(document_type: "passport", issuing_country: "DE", document_number: "C01X#{user.id}T47",
                                    national_id: nil, legal_name: "Person #{user.id}", date_of_birth: Date.new(1990, 8, 12))
      end

      def call_for(user) = create(:verification, :call_scheduled, user:)

      # The errors of the decision, as one string ("" on success).
      def decide(verification, by:)
        match_account!(verification.user, identifiers(verification.user))
        result = VerificationFlow.decide(verification, by:, outcome: "verified", reason: "Face matched the ID on the call.",
                                                       age_consistent: true, region_consistent: true,
                                                       identifiers: identifiers(verification.user),
                                                       residency: { us_resident: true, us_state: "MA", evidence_type: "id_document" })
        result.errors.values.join(" ")
      end

      before { described_class.bootstrap!(circle, by: owner) }

      it "lets each unverified member verify only the person after them" do
        expect(decide(call_for(kieran), by: adam)).to include("only verify the person after you")
        expect(decide(call_for(create(:user, :verified)), by: jasper)).to include("only verify the person after you")

        expect(decide(call_for(kieran), by: jasper)).to eq("")
        expect(decide(call_for(adam), by: kieran)).to eq("")
        expect(decide(call_for(jasper), by: adam)).to eq("")
      end

      it "ends with each member verified by their planned verifier" do
        [[kieran, jasper], [adam, kieran], [jasper, adam]].each { |user, verifier| decide(call_for(user), by: verifier) }

        expect(described_class.bootstrap_status.map { |row| row[:verified_by] }).to eq([adam, jasper, kieran])
        expect(circle.map { |user| described_class.preconditions_met?(user.reload) }).to all(be(true))
      end

      it "lets a bootstrap member verify anyone once they are verified" do
        decide(call_for(kieran), by: jasper)

        expect(decide(call_for(create(:user, :verified)), by: kieran)).to eq("")
      end

      it "does not limit a member who joined through a proposal" do
        expect(decide(call_for(create(:user, :verified)), by: create(:user, :identity_team))).to eq("")
      end
    end

    it "needs at least two people" do
      expect(described_class.bootstrap!([jasper], by: owner)).not_to be_success
    end

    it "needs each person to be an adult, and does not ask for an NDA" do
      minor = create(:user, :verified, :minor, first_name: "Young")

      result = described_class.bootstrap!([jasper, kieran, minor], by: owner)

      expect(result.message).to include("Young", "15 years old")
      expect(result.message).not_to include("Jasper", "Kieran", "NDA")
      expect(jasper.reload.identity_team).to be(false)
    end
  end

  describe "a deleted account" do
    it "takes an identity team member off the team, logs it, tells the board and sends key_holders_changed" do
      board_member
      member = verified_member(:key_holder)
      open_proposal = propose("set_lead", member)
      payloads = []
      subscriber = ActiveSupport::Notifications.subscribe(described_class::KEY_HOLDERS_CHANGED) { |*, payload| payloads << payload }

      perform_enqueued_jobs { DeletionPipeline.run!(create(:deletion_request, :approved, user: member)) }

      event = IdentityGovernanceEvent.find_by!(kind: "member_removed")
      expect(event.data).to include("reason" => "The account was deleted.", "was_key_holder" => true)
      expect(event.subject_id).to be_nil
      expect(open_proposal.reload).to be_cancelled
      expect(payloads.sole).to include(change: :removed, holder_ids: [])
      expect(ActionMailer::Base.deliveries.map(&:subject)).to include(a_string_including("removed from the identity team"))
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  describe "a board change" do
    it "is logged and every board member before and after the change is told" do
      board_member
      leaving = other_board_member
      leaving.update!(is_board: false)

      event = perform_enqueued_jobs { described_class.board_changed!(leaving, by: owner) }

      expect(event).to have_attributes(kind: "board_member_removed", actor: owner, subject: leaving)
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly(owner.email, board_member.email, leaving.email)
    end
  end

  describe "patch lead changes" do
    let(:lead) { ready_candidate(first_name: "Adam") }

    def propose_lead(by: owner, scope: "ganymede", subject: lead)
      described_class.propose(kind: "add_patch_lead", subject:, by:, reason: "Leads Ganymede.", scope:)
    end

    it "needs an owner to propose with a program and a different board member to approve" do
      result = propose_lead
      expect(result).to be_success
      proposal = result.record
      expect(proposal).to have_attributes(scope: "ganymede", required_approver_ids: [])
      expect(proposal.description).to eq("make #{lead.full_name} the patch lead of Project Ganymede")

      expect(described_class.approve(proposal, by: owner)).not_to be_success
      expect(lead.reload.has_role?("patch_lead", scope: "ganymede")).to be(false)
      expect(described_class.approve(proposal, by: board_member)).to be_success

      expect(lead.reload.has_role?("patch_lead", scope: "ganymede")).to be(true)
      expect(KnotGrants.patch_lead?(lead, "ganymede")).to be(true)
      expect(UserRole.for_role("patch_lead").sole).to have_attributes(identity_governance_proposal: proposal, granted_by: board_member)
      expect(proposal.events.find_by(kind: "applied").summary).to include("patch lead of Project Ganymede")
    end

    it "needs a program from config/kyc/knot.yml" do
      expect(propose_lead(scope: nil).errors).to include(scope: "must be one of: ganymede")
      expect(propose_lead(scope: "europa").errors).to include(scope: "must be one of: ganymede")
      expect(IdentityGovernanceProposal.count).to eq(0)
    end

    it "does not let a non-owner propose, and refuses a patch lead who already leads the program" do
      expect(propose_lead(by: board_member)).not_to be_success

      RoleGrants.grant!(lead, "patch_lead", scope: "ganymede")
      expect(propose_lead.message).to include("already the patch lead of ganymede")
    end

    it "needs the patch lead to be ID-verified by another verifier, at the proposal and at the approval" do
      unverified = create(:user, :verified)
      expect(propose_lead(subject: unverified).message).to include("must be verified (by another verifier)")

      proposal = propose_lead.record
      lead.latest_verification.update_columns(verifier_id: lead.id) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.approve(proposal, by: board_member).message).to include("must be verified (by another verifier)")
      expect(lead.reload.has_role?("patch_lead", scope: "ganymede")).to be(false)
    end

    it "does not let the subject approve a proposal about themselves" do
      lead.update!(is_board: true)
      proposal = propose_lead.record

      expect(described_class.approve(proposal, by: lead)).not_to be_success
    end
  end

  describe "the rules come from config/roles.yml" do
    it "offers only the kinds whose role has a proposal rule" do
      expect(described_class.proposable_kinds).to eq(IdentityGovernanceProposal::KINDS)

      raw = YAML.safe_load_file(RoleRegistry::PATH)
      raw["roles"]["identity_lead"]["revoke"] = { "rule" => "owner" }
      allow(RoleRegistry).to receive(:definitions).and_return(RoleRegistry.parse(raw))

      expect(described_class.proposable_kinds).not_to include("clear_lead")
      lead = create(:user, :identity_lead)
      result = described_class.propose(kind: "clear_lead", subject: lead, by: owner, reason: "x")
      expect(result.message).to include("does not need a proposal")
    end

    it "asks every board member when the config gives a role the all-board rule" do
      board_member
      other_board_member
      raw = YAML.safe_load_file(RoleRegistry::PATH)
      raw["roles"]["patch_lead"]["grant"]["rule"] = "owner_proposes_all_board_approve"
      allow(RoleRegistry).to receive(:definitions).and_return(RoleRegistry.parse(raw))

      proposal = described_class.propose(kind: "add_patch_lead", subject: ready_candidate, by: owner,
                                         reason: "x", scope: "ganymede").record

      expect(proposal.required_approver_ids).to contain_exactly(owner.id, board_member.id, other_board_member.id)
      described_class.approve(proposal, by: board_member)
      expect(proposal.reload).to be_pending
    end
  end

  describe "who reads the governance page" do
    it "allows owners, board members and identity team leads only" do
      expect(described_class.can_view?(create(:user, :owner, :verified))).to be(true)
      expect(described_class.can_view?(board_member)).to be(true)
      expect(described_class.can_view?(create(:user, :identity_lead))).to be(true)
      expect(described_class.can_view?(create(:user, :identity_team))).to be(false)
      expect(described_class.can_view?(create(:user, :superadmin, :verified))).to be(false)
      expect(described_class.can_view?(nil)).to be(false)
    end
  end
end
