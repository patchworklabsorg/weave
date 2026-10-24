# frozen_string_literal: true

require "rails_helper"

# ID checks open after the key ceremony: until a key set is active, no image
# can be sealed when pre-review ends (see VerificationFlow.submission_blocker).
RSpec.describe "Identity verification before the key ceremony", type: :request do
  let(:image) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png") }
  let(:params) { { document_type: "passport", id_document: image, data_notice_read: "1" } }

  it "tells a member that ID checks open soon and takes no upload" do
    sign_in_via_magic_link(create(:user, :verified))

    get verification_path
    expect(response.body).to include(I18n.t("verification.blockers.not_open"))
    expect { post verification_path, params: }.not_to change(Verification, :count)
  end

  it "lets the identity team submit, for the bootstrap circle" do
    expect(VerificationFlow.submission_blocker(create(:user, :verified, identity_team: true))).to be_nil
  end

  it "opens for everyone once a key set is active" do
    active_key_set_without_holders

    expect(VerificationFlow.submission_blocker(create(:user, :verified))).to be_nil
  end
end
