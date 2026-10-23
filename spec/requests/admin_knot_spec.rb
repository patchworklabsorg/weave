# frozen_string_literal: true

require "rails_helper"

# The Knot admin pages: the request queue, the Knot page, two-key changes and
# program grants on the admin user page.
RSpec.describe "Admin Knot", type: :request do
  let(:knot) { create(:knot, :with_audit) }
  let(:member) { knot.user }
  let(:asker) { create(:user, :identity_team) }
  let(:signer) { create(:user, :identity_team) }

  describe "access" do
    it "turns away an admin who is not on the identity team, the board or a patch lead" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get admin_knots_path
      expect(response).to redirect_to(admin_root_path)

      get admin_knot_path(knot)
      expect(response).to redirect_to(admin_root_path)
    end

    it "lets a board member open the queue but not the Knot page" do
      sign_in_via_magic_link(create(:user, :admin, :verified, is_board: true))

      get admin_knots_path
      expect(response).to have_http_status(:ok)

      get admin_knot_path(knot)
      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe "the Knot page" do
    before { sign_in_via_magic_link(asker) }

    it "finds a Knot by its public id and not by its database id" do
      expect(admin_knot_path(knot)).to eq("/admin/knots/#{knot.hashid}")

      get "/admin/knots/#{knot.id}"

      expect(response).to have_http_status(:not_found)
    end

    it "shows the flag, the grants and hash counts, never a digest" do
      hash = create(:knot_hash, knot:, kind: "document")
      create(:program_grant, knot:)

      get admin_knot_path(knot)

      expect(response.body).to include("Fraud flag: <strong>no</strong>", "Project Ganymede: 1", "Document 1")
      expect(response.body).not_to include(hash.digest)
    end

    it "shows the manual review on the attempt page" do
      verification = create(:verification, :call_scheduled, knot_review_reason: "soft_match")

      get identity_verification_path(verification)

      expect(response.body).to include("Manual review", "can never fail or block")
    end
  end

  describe "a two-key flag change" do
    it "asks, then a second identity team member signs off in the queue" do
      sign_in_via_magic_link(asker)
      post request_blacklist_admin_knot_path(knot), params: { blacklisted: "1", reason: "Cycled a grant." }
      expect(knot.reload).not_to be_blacklisted

      sign_in_via_magic_link(signer)
      get admin_knots_path
      expect(response.body).to include("Set the fraud flag", "Cycled a grant.")

      patch sign_off_admin_knot_change_request_path(KnotChangeRequest.sole)
      expect(knot.reload).to be_blacklisted
    end

    it "does not let the requester sign off" do
      sign_in_via_magic_link(asker)
      post request_blacklist_admin_knot_path(knot), params: { blacklisted: "1", reason: "Cycled a grant." }

      patch sign_off_admin_knot_change_request_path(KnotChangeRequest.sole)

      expect(knot.reload).not_to be_blacklisted
      expect(flash[:alert]).to include("second, different person")
    end
  end

  describe "a name change" do
    it "keeps only hashes on the request and adds them at sign-off" do
      sign_in_via_magic_link(asker)
      post request_name_change_admin_knot_path(knot), params: {
        evidence: "change_of_name_record", note: "Saw the deed poll on a call.",
        identifiers: { legal_name: "Erika Neu", date_of_birth: "1990-08-12" }
      }
      request = KnotChangeRequest.sole
      expect(request.digests.to_json).not_to include("Neu")

      sign_in_via_magic_link(signer)
      patch sign_off_admin_knot_change_request_path(request)

      expect(knot.reload.knot_hashes.pluck(:kind)).to eq(["soft"])
    end
  end

  describe "program grants on the admin user page" do
    let(:lead) { create(:user, :admin, :verified, :patch_lead) }

    before do
      allow(KnotSettings).to receive(:config).and_return({ programs: { ganymede: { name: "Project Ganymede", grant_cap: 1 } } })
    end

    it "lets the patch lead record a grant, then ask for an override that a board member signs off" do
      sign_in_via_magic_link(lead)
      get admin_user_path(member)
      expect(response.body).to include("Project Ganymede: 0 received of 1 allowed", "Record a grant")

      post admin_user_program_grants_path(member), params: { program: "ganymede" }
      expect(knot.program_grants.count).to eq(1)

      post admin_user_program_grants_path(member), params: { program: "ganymede" }
      expect(knot.program_grants.count).to eq(1)

      post override_admin_user_program_grants_path(member), params: { program: "ganymede", reason: "A new, separate project." }
      sign_in_via_magic_link(create(:user, :admin, :verified, is_board: true))
      patch sign_off_admin_knot_change_request_path(KnotChangeRequest.sole)

      expect(knot.program_grants.count).to eq(2)
    end

    it "shows the fraud flag to the identity team only" do
      knot.update!(blacklisted: true)

      sign_in_via_magic_link(create(:user, :superadmin, :verified))
      get admin_user_path(member)
      expect(response.body).not_to include("Fraud flag")

      sign_in_via_magic_link(asker)
      get admin_user_path(member)
      expect(response.body).to include("Fraud flag: yes")
    end

    it "does not let another admin record a grant" do
      sign_in_via_magic_link(create(:user, :superadmin, :verified))

      post admin_user_program_grants_path(member), params: { program: "ganymede" }

      expect(knot.program_grants.count).to eq(0)
    end
  end

  describe "the member page" do
    it "tells the member about the Knot and the name change path after a pass" do
      create(:verification, :verified, user: member)
      sign_in_via_magic_link(member)

      get verification_path

      expect(response.body).to include("called the Knot", "legal name change")
    end
  end
end
