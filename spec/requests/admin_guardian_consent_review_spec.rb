# frozen_string_literal: true

require "rails_helper"

# Flagged guardian consents wait in a queue until an admin checks them.
RSpec.describe "Admin guardian consent review", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin, :verified) }
  let(:member) { create(:user, :verified, :minor, first_name: "Ada") }
  let!(:flagged) { create(:guardian_consent, :granted, user: member, flags: ["quick_grant"]) }

  it "lists flagged consents that nobody has checked" do
    create(:guardian_consent, :granted, flags: [])
    sign_in_via_magic_link(admin)

    get admin_guardian_consents_path

    expect(response.body).to include("Ada", "within 5 minutes")
    expect(response.body.scan(%(value="Mark as checked")).size).to eq(1)
  end

  it "records who checked a consent and how" do
    sign_in_via_magic_link(admin)

    patch review_admin_guardian_consent_path(flagged), params: { note: "Phone call with the mother" }

    expect(flagged.reload).to have_attributes(reviewed_by: admin, review_note: "Phone call with the mother")
    expect(GuardianConsent.needs_review).to be_empty
  end

  it "needs a note" do
    sign_in_via_magic_link(admin)

    patch review_admin_guardian_consent_path(flagged), params: { note: " " }

    expect(flagged.reload.reviewed_at).to be_nil
  end

  it "is for admins only" do
    sign_in_via_magic_link(member)

    get admin_guardian_consents_path

    expect(response).to redirect_to(login_path)
  end

  describe "flagging on grant" do
    let(:token) { SecureRandom.urlsafe_base64(32) }

    it "flags a quick consent and tells the admins" do
      consent = create(:guardian_consent, user: create(:user, :verified, :minor), raw_token: token, sent_at: 1.minute.ago)

      expect { post guardian_consent_path(token:), params: { confirm: "1", signed_name: "Grace Hopper", fingerprint: "fp-1" } }
        .to have_enqueued_mail(AdminMailer, :guardian_consent_flagged)

      expect(consent.reload).to have_attributes(flags: include("quick_grant"), granted_fingerprint: "fp-1")
    end
  end
end
