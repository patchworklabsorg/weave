# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdDocumentVault do
  include ActiveJob::TestHelper

  let(:member) { create(:user, :verified) }
  let(:verifier) { create(:user, :identity_team) }
  let(:verification) { create(:verification, user: member) }

  def image = Rails.root.join("spec/fixtures/files/id_document.png").binread

  def open_with(private_key, attempt)
    sealed = attempt.sealed_document
    data_key = described_class.open_data_key(attempt, private_key)
    KeyCustody::Crypto.decrypt(sealed.ciphertext.download, key: data_key, aad: "verification:#{attempt.id}")
  end

  describe "sealing when pre-review ends" do
    let!(:key_pair) { active_key_set_without_holders }

    before { VerificationFlow.start_pre_review(verification, by: verifier) }

    it "lets the pre-reviewer see the image before any key holder is involved" do
      expect(VerificationFlow.pre_review_document(verification, by: verifier)).to eq(image)
      expect(verification.sealed_document).to be_nil
    end

    it "seals the image and destroys the Lockbox copy at Document OK" do
      expect(VerificationFlow.approve_document(verification, by: verifier)).to be(true)

      verification.reload
      expect(verification.id_document).not_to be_attached
      expect(verification.sealed_document).to have_attributes(key_set: key_pair.first, content_type: "image/png", extension: ".png")
      expect(verification).to be_document_sealed
      expect(verification.events.where(kind: "document_sealed")).to exist
      expect(open_with(key_pair.last, verification)).to eq(image)
    end

    it "seals the image when the member is sent back for a new document" do
      expect(VerificationFlow.reject_document(verification, by: verifier, note: "The photo is blurry.")).to be(true)

      verification.reload
      expect(verification.id_document).not_to be_attached
      expect(open_with(key_pair.last, verification)).to eq(image)
    end

    it "closes the pre-review path after the seal: only break-glass opens the image" do
      VerificationFlow.approve_document(verification, by: verifier)

      expect(VerificationFlow.pre_review_document(verification.reload, by: verifier)).to be_nil
      expect(described_class.pre_review_read(verification)).to be_nil
    end

    it "does not touch the sealed image when the call time is recorded or moved" do
      VerificationFlow.approve_document(verification, by: verifier)
      sealed = verification.reload.sealed_document

      expect(VerificationFlow.schedule_call(verification, by: verifier, at: 2.days.from_now)).to be(true)
      expect(VerificationFlow.schedule_call(verification, by: verifier, at: 3.days.from_now)).to be(true)
      expect(verification.reload.sealed_document).to eq(sealed)
      expect(verification.events.where(kind: "document_sealed").count).to eq(1)
    end

    it "keeps the sealed image away from the server key: the ciphertext is no Lockbox value" do
      VerificationFlow.approve_document(verification, by: verifier)

      ciphertext = verification.reload.sealed_document.ciphertext.download
      expect(ciphertext).not_to include(image.byteslice(0, 64))
      expect { Lockbox.new(key: Lockbox.attribute_key(table: "verifications", attribute: "id_document")).decrypt(ciphertext) }
        .to raise_error(Lockbox::Error)
    end
  end

  describe "when key custody is not set up" do
    it "keeps pre-review open and the image under Lockbox" do
      VerificationFlow.start_pre_review(verification, by: verifier)

      expect(VerificationFlow.approve_document(verification, by: verifier)).to be(false)
      expect(VerificationFlow.reject_document(verification, by: verifier, note: "Blurry photo")).to be(false)
      expect(verification.reload).to be_pre_review
      expect(verification.id_document).to be_attached
      expect { described_class.seal!(verification) }.to raise_error(KeyCustody::NotSetUp)
    end
  end

  it "seals to a compromised set until its rotation is done" do
    key_set, private_key = active_key_set_without_holders
    key_set.update!(status: "compromised", compromised_at: Time.current, compromised_reason: "holder_lost_all_keys")

    described_class.seal!(verification)

    expect(verification.reload.sealed_document.key_set).to eq(key_set)
    expect(open_with(private_key, verification)).to eq(image)
  end

  it "has nothing to seal for an attempt with no image" do
    active_key_set_without_holders
    attempt = Verification.create!(user: create(:user, :verified), verification_method: "digital_id_call")

    expect(described_class.seal!(attempt)).to be(false)
  end

  describe ".purge!" do
    it "removes the sealed copy and its file" do
      active_key_set_without_holders
      described_class.seal!(verification)

      expect(described_class.purge!(verification.reload)).to be(true)
      expect(SealedIdDocument.where(verification_id: verification.id)).to be_empty
      expect(verification.reload).not_to be_document_stored
    end

    it "purges a sealed image after the pass window" do
      active_key_set_without_holders
      passed = create(:verification, :verified, user: member, decided_at: (VerificationSettings.purge_image_after_pass + 1.day).ago)
      described_class.seal!(passed)

      PurgeVerificationDocumentsJob.perform_now

      expect(passed.reload.document_purged_at).to be_present
      expect(passed.sealed_document).to be_nil
    end

    it "purges a sealed image when the account is deleted" do
      active_key_set_without_holders
      passed = create(:verification, :verified, user: member)
      described_class.seal!(passed)
      request = create(:deletion_request, :approved, user: member)

      DeletionPipeline.run!(request.reload)

      expect(passed.reload.document_purged_at).to be_present
      expect(SealedIdDocument.where(verification_id: passed.id)).to be_empty
    end
  end
end
