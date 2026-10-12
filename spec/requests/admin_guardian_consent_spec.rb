# frozen_string_literal: true

require "rails_helper"

# Admin tools for a member's parent or guardian consent, on the admin user
# page.
RSpec.describe "Admin guardian consent", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:member) { create(:user, :verified, :minor, first_name: "Ada") }

  it "shows where the consent stands" do
    create(:guardian_consent, user: member, guardian_email: "grace@example.org")
    sign_in_via_magic_link(admin)

    get admin_user_path(member)

    expect(response.body).to include("Guardian consent", "grace@example.org", "Send the request again")
    expect(response.body).not_to include("Record consent given offline")
  end

  it "does not show the section for an adult with nothing on file" do
    sign_in_via_magic_link(admin)

    get admin_user_path(create(:user, :verified))

    expect(response.body).not_to include("Guardian consent")
  end

  it "lets an admin send the request again after the cooldown" do
    consent = create(:guardian_consent, user: member, sent_at: 1.hour.ago)
    sign_in_via_magic_link(admin)

    expect { post resend_admin_user_guardian_consent_path(member, consent) }
      .to have_enqueued_mail(GuardianConsentMailer, :request_consent)
    expect(flash[:notice]).to include("again")
  end

  describe "recording consent given offline" do
    let(:params) { { guardian_name: "Grace Hopper", guardian_email: "grace@example.org", note: "Paper form in the drive" } }

    it "lets a superadmin record it, which starts the Slack invite" do
      sign_in_via_magic_link(superadmin)

      expect { post admin_user_guardian_consents_path(member), params: }
        .to have_enqueued_job(InviteToSlackJob).with(member.id)

      consent = member.guardian_consents.sole
      expect(consent).to have_attributes(status: "granted", recorded_by: superadmin, note: "Paper form in the drive")
      expect(member.reload.guardian_consent_missing?).to be(false)
    end

    it "needs a note" do
      sign_in_via_magic_link(superadmin)

      post admin_user_guardian_consents_path(member), params: params.merge(note: " ")

      expect(flash[:alert]).to include("Note can't be blank")
      expect(member.guardian_consents).to be_empty
    end

    it "does not let a plain admin record it" do
      sign_in_via_magic_link(admin)

      post admin_user_guardian_consents_path(member), params: params

      expect(member.guardian_consents).to be_empty
    end
  end

  describe "revoking" do
    let!(:consent) { create(:guardian_consent, :granted, user: member) }

    it "lets a superadmin revoke and removes app access" do
      sign_in_via_magic_link(superadmin)

      expect { patch revoke_admin_user_guardian_consent_path(member, consent) }
        .to have_enqueued_job(RevokeLostAppAccessJob).with(user_id: member.id)
        .and have_enqueued_mail(GuardianConsentMailer, :revoked)

      expect(consent.reload).to have_attributes(status: "revoked", revoked_by: superadmin)
    end

    it "does not let a plain admin revoke" do
      sign_in_via_magic_link(admin)

      patch revoke_admin_user_guardian_consent_path(member, consent)

      expect(consent.reload).to be_granted
    end
  end

  it "refuses a consent that belongs to another member" do
    other = create(:guardian_consent, :granted)
    sign_in_via_magic_link(superadmin)

    patch revoke_admin_user_guardian_consent_path(member, other)

    expect(response).to have_http_status(:not_found)
    expect(other.reload).to be_granted
  end

  describe "recording a verified guardian" do
    let!(:consent) { create(:guardian_consent, :granted, user: member, flags: ["spot_check"]) }

    it "lets a superadmin verify, which also counts as the review" do
      sign_in_via_magic_link(superadmin)

      patch verify_admin_user_guardian_consent_path(member, consent), params: { note: "Signed form in Drive, call on Oct 12" }

      expect(consent.reload).to have_attributes(verified_by: superadmin, verification_note: "Signed form in Drive, call on Oct 12")
      expect(consent).not_to be_needs_review
      expect(member.reload.guardian_verified?).to be(true)
    end

    it "needs a note" do
      sign_in_via_magic_link(superadmin)

      patch verify_admin_user_guardian_consent_path(member, consent), params: { note: "" }

      expect(consent.reload.verified_at).to be_nil
    end

    it "does not let a plain admin verify" do
      sign_in_via_magic_link(admin)

      patch verify_admin_user_guardian_consent_path(member, consent), params: { note: "Signed form" }

      expect(consent.reload.verified_at).to be_nil
    end

    it "ends with a revoke" do
      consent.update!(verified_at: 1.day.ago)
      consent.record_revoke!

      expect(member.reload.guardian_verified?).to be(false)
    end
  end
end
