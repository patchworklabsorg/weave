# frozen_string_literal: true

require "rails_helper"

# ID checks open after the key ceremony and pause while the key set is
# compromised: pre-review seals each image to the active key set (see
# VerificationFlow.submission_blocker and KeyCustody.open?).
RSpec.describe "Identity verification before the key ceremony", type: :request do
  let(:image) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png") }
  let(:params) { { document_type: "passport", id_document: image, data_notice_read: "1" } }

  it "tells a member that ID checks open soon and takes no upload" do
    sign_in_via_magic_link(create(:user, :verified))

    get verification_path
    expect(response.body).to include(I18n.t("verification.blockers.not_open"))
    expect(response.body).not_to include(I18n.t("residency.page.identity_first"))
    expect { post verification_path, params: }.not_to change(Verification, :count)
  end

  it "keeps the identity team out too: the bootstrap circle runs after the ceremony" do
    expect(VerificationFlow.submission_blocker(create(:user, :verified, identity_team: true))).to eq(:not_open)
  end

  it "still shows an attempt that started before the gate as in progress" do
    member = create(:user, :verified)
    create(:verification, user: member)

    expect(VerificationFlow.submission_blocker(member)).to eq(:in_progress)
  end

  it "keeps the residency check closed" do
    expect(ResidencyFlow.submission_blocker(create(:user, :verified))).to eq(:not_open)
  end

  it "opens once a key set is active, and pauses while it is compromised" do
    key_set, = active_key_set_without_holders
    member = create(:user, :verified)
    expect(VerificationFlow.submission_blocker(member)).to be_nil

    key_set.update!(status: "compromised")

    expect(VerificationFlow.submission_blocker(member)).to eq(:not_open)
  end
end
