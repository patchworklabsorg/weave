# frozen_string_literal: true

require "rails_helper"

# The identity team governance pages (/identity/governance).
RSpec.describe "Identity team governance pages", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, :owner, :verified, first_name: "Olive") }
  let(:board_member) { create(:user, :verified, is_board: true, first_name: "Bo") }

  def ready_candidate
    user = create(:user, :verified, first_name: "Cara")
    create(:verification, :verified, user:)
    create(:identity_nda, user:)
    user
  end

  describe "access" do
    it "lets an owner in" do
      sign_in_via_magic_link(owner)

      get identity_governance_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Identity team governance", "Propose a change", "Record a signed NDA")
    end

    it "lets a board member without the admin role in, read only" do
      sign_in_via_magic_link(board_member)

      get identity_governance_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Propose a change")
    end

    it "lets an identity team lead in, with the removal form" do
      lead = create(:user, :verified, identity_team: true, identity_lead: true)
      create(:user, :identity_team, first_name: "Tess")
      sign_in_via_magic_link(lead)

      get identity_governance_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Remove now")
    end

    it "keeps out a plain verifier and a superadmin" do
      [create(:user, :identity_team), create(:user, :superadmin, :verified)].each do |user|
        sign_in_via_magic_link(user)

        get identity_governance_path

        expect(response).to redirect_to(root_path)
      end
    end

    it "keeps out an admin who impersonates an owner" do
      superadmin = create(:user, :owner, :verified)
      sign_in_via_magic_link(superadmin)
      post impersonate_admin_user_path(create(:user, :verified, is_board: true))

      get identity_governance_path

      expect(response).to redirect_to(root_path)
    end
  end

  # Every route of the identity area, for people who must not use it. Each
  # request must redirect and change nothing.
  describe "every identity route for outsiders" do
    let(:candidate) { ready_candidate }
    let(:verification) { create(:verification, :call_scheduled) }
    let(:proposal) do
      create(:user, :verified, is_board: true)
      IdentityGovernance.propose(kind: "add_member", subject: candidate, by: owner, reason: "Calls.").record
    end

    def identity_requests
      record = create(:break_glass_record, verification: create(:verification, :verified))
      [
        [:get, identity_verifications_path], [:get, identity_verification_path(verification)],
        [:patch, start_pre_review_identity_verification_path(verification)],
        [:post, image_identity_verification_path(verification)],
        [:patch, decide_identity_verification_path(verification), { outcome: "verified", reason: "x" }],
        [:post, identity_verification_break_glass_records_path(verification), { reason: "x" }],
        [:get, identity_break_glass_records_path], [:patch, approve_identity_break_glass_record_path(record)],
        [:post, image_identity_break_glass_record_path(record)]
      ]
    end

    def governance_requests
      [
        [:get, identity_governance_path], [:get, identity_governance_proposal_path(proposal)],
        [:post, identity_governance_proposals_path, { kind: "add_member", person: candidate.email, reason: "x" }],
        [:patch, approve_identity_governance_proposal_path(proposal)],
        [:patch, reject_identity_governance_proposal_path(proposal), { reason: "x" }],
        [:patch, withdraw_identity_governance_proposal_path(proposal)],
        [:post, identity_ndas_path, { person: candidate.email, signed_on: Date.current.iso8601, nda_version: "v1", signature_reference: "m" }],
        [:post, identity_team_removals_path, { user_id: create(:user, :identity_team).p_id, reason: "x" }]
      ]
    end

    def expect_all_refused(requests)
      requests.each do |verb, path, params|
        public_send(verb, path, params:)
        expect(response).to have_http_status(:redirect), "#{verb} #{path} gave #{response.status}"
      end
    end

    def expect_nothing_changed
      expect(proposal.reload).to be_pending
      expect(candidate.reload.identity_team).to be(false)
      expect(IdentityGovernanceEvent.where(kind: %w[member_removed approved nda_recorded])).to be_empty
      expect(IdentityNda.where(user: candidate).count).to eq(1)
      expect(IdentityGovernanceApproval.count).to eq(0)
      expect(verification.reload).to be_call_scheduled
      expect(BreakGlassRecord.where(reason: "x")).to be_empty
      expect(BreakGlassApproval.count).to eq(0)
      expect(BreakGlassDecryption.count).to eq(0)
      expect(VerificationEvent.where(kind: "document_viewed")).to be_empty
    end

    it "refuses a plain member, an admin and a superadmin without the flag, on every route" do
      [create(:user, :verified), create(:user, :admin, :verified), create(:user, :superadmin, :verified)].each do |user|
        sign_in_via_magic_link(user)
        expect_all_refused(identity_requests + governance_requests)
      end
      expect_nothing_changed
    end

    it "refuses a signed-out visitor on every route" do
      expect_all_refused(identity_requests + governance_requests)
      expect_nothing_changed
    end

    it "refuses a plain verifier on every governance route" do
      sign_in_via_magic_link(create(:user, :identity_team))
      expect_all_refused(governance_requests)
      expect_nothing_changed
    end
  end

  describe "the two-person flow for a verifier" do
    it "lets an owner propose, shows the preconditions, and does not let the owner approve" do
      candidate = ready_candidate
      sign_in_via_magic_link(owner)

      post identity_governance_proposals_path, params: { person: candidate.email, kind: "add_member", reason: "Runs calls." }
      proposal = IdentityGovernanceProposal.last
      expect(response).to redirect_to(identity_governance_proposal_path(proposal))

      get identity_governance_proposal_path(proposal)
      expect(response.body).to include("Preconditions", "verified by another verifier", "signed NDA on record")
      expect(response.body).not_to include('value="Approve"')

      patch approve_identity_governance_proposal_path(proposal)
      expect(candidate.reload.identity_team).to be(false)
    end

    it "lets a different board member approve, which applies the change" do
      candidate = ready_candidate
      proposal = IdentityGovernance.propose(kind: "add_member", subject: candidate, by: owner, reason: "Runs calls.").record
      sign_in_via_magic_link(board_member)

      get identity_governance_proposal_path(proposal)
      expect(response.body).to include('value="Approve"')
      patch approve_identity_governance_proposal_path(proposal)

      expect(candidate.reload.identity_team).to be(true)
      expect(flash[:notice]).to include("applied")
    end

    it "finds a proposal by its public id and not by its database id" do
      candidate = ready_candidate
      proposal = IdentityGovernance.propose(kind: "add_member", subject: candidate, by: owner, reason: "Runs calls.").record
      sign_in_via_magic_link(board_member)

      expect(identity_governance_proposal_path(proposal)).to eq("/identity/governance_proposals/#{proposal.hashid}")
      patch "/identity/governance_proposals/#{proposal.id}/approve"

      expect(response).to have_http_status(:not_found)
      expect(candidate.reload.identity_team).to be(false)
    end

    it "finds the person by Weave ID too" do
      candidate = ready_candidate
      sign_in_via_magic_link(owner)

      post identity_governance_proposals_path, params: { person: candidate.p_id, kind: "add_member", reason: "Runs calls." }

      expect(IdentityGovernanceProposal.last.subject).to eq(candidate)
    end

    it "does not let a board member propose" do
      sign_in_via_magic_link(board_member)

      post identity_governance_proposals_path, params: { person: ready_candidate.email, kind: "add_member", reason: "x" }

      expect(IdentityGovernanceProposal.count).to eq(0)
      expect(flash[:alert]).to include("Only an owner")
    end

    it "lets a board member reject with a reason" do
      proposal = IdentityGovernance.propose(kind: "add_member", subject: ready_candidate, by: owner, reason: "x").record
      sign_in_via_magic_link(board_member)

      patch reject_identity_governance_proposal_path(proposal), params: { reason: "Not this term." }

      expect(proposal.reload).to be_rejected
    end

    it "lets the owner withdraw" do
      proposal = IdentityGovernance.propose(kind: "add_member", subject: ready_candidate, by: owner, reason: "x").record
      sign_in_via_magic_link(owner)

      patch withdraw_identity_governance_proposal_path(proposal)

      expect(proposal.reload).to be_withdrawn
    end
  end

  describe "NDA records" do
    it "lets an owner record an NDA by hand" do
      person = create(:user, :verified)
      sign_in_via_magic_link(owner)

      post identity_ndas_path, params: { person: person.email, signed_on: "2026-10-01", nda_version: "v1", signature_reference: "Adobe agreement 7" }

      expect(person.current_identity_nda).to have_attributes(signed_on: Date.new(2026, 10, 1), signature_reference: "Adobe agreement 7")
    end

    it "does not let a board member record one" do
      sign_in_via_magic_link(board_member)

      post identity_ndas_path, params: { person: create(:user).email, signed_on: "2026-10-01", nda_version: "v1", signature_reference: "x" }

      expect(IdentityNda.count).to eq(0)
    end
  end

  describe "removal" do
    it "lets a lead without the admin role remove a member at once, and tells the board" do
      board_member
      lead = create(:user, :verified, identity_team: true, identity_lead: true)
      member = create(:user, :identity_team)
      sign_in_via_magic_link(lead)

      expect { post identity_team_removals_path, params: { user_id: member.p_id, reason: "Broke the NDA." } }
        .to have_enqueued_mail(IdentityGovernanceMailer, :member_removed)

      expect(member.reload.identity_team).to be(false)
      expect(PrivilegedAttributeChange.where(user_id: member.id, attribute_name: "identity_team", new_value: "false").sole)
        .to have_attributes(new_value: "false", actor_id: lead.id)
    end

    it "does not let a board member who is not an owner remove" do
      member = create(:user, :identity_team)
      sign_in_via_magic_link(board_member)

      post identity_team_removals_path, params: { user_id: member.p_id, reason: "x" }

      expect(member.reload.identity_team).to be(true)
    end
  end

  describe "the old owner flag form" do
    it "is gone from the admin panel" do
      sign_in_via_magic_link(owner)

      patch "/admin/users/#{create(:user).p_id}/identity_team", params: { identity_team: "1" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the board report" do
    it "lists the governance log for a board member" do
      board = create(:user, :admin, :verified, is_board: true)
      member = create(:user, :identity_team, first_name: "Rae")
      IdentityGovernance.remove_member(member, by: owner, reason: "Left the org.")
      sign_in_via_magic_link(board)

      get admin_break_glass_report_path

      expect(response.body).to include("Identity team governance", "removed Rae", "Left the org.")
    end

    it "lists the month's changes to privileged attributes, in the page and the email" do
      board = create(:user, :admin, :verified, is_board: true)
      member = create(:user, :identity_team, first_name: "Rae")
      IdentityGovernance.remove_member(member, by: owner, reason: "Left the org.")
      sign_in_via_magic_link(board)

      get admin_break_glass_report_path

      expect(response.body).to include("Changes to privileged attributes", "#{member.p_id}: identity_team true -&gt; false",
                                       "By Olive")
      mail = BreakGlassMailer.board_report(board, Date.current.beginning_of_month.iso8601)
      expect(mail.body.encoded).to include("Changes to privileged attributes (permanent log)", "#{member.p_id}: identity_team true -> false")
    end
  end

  describe "the permanent log on the governance page" do
    it "shows every change to a privileged attribute" do
      member = create(:user, :verified)
      member.update_column(:is_board, true) # rubocop:disable Rails/SkipsModelValidations
      sign_in_via_magic_link(owner)

      get identity_governance_path

      expect(response.body).to include("Permanent log of privileged attributes", "#{member.p_id}: is_board false -&gt; true")
    end
  end
end
