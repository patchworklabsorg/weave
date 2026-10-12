# frozen_string_literal: true

# == Schema Information
#
# Table name: guardian_consents
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  account_deleted_at        :datetime
#  expires_at                :datetime
#  flags                     :jsonb            not null
#  granted_at                :datetime
#  granted_fingerprint       :string
#  granted_ip                :string
#  granted_user_agent        :string
#  guardian_email_ciphertext :text
#  guardian_name_ciphertext  :text
#  note                      :text
#  review_note               :text
#  reviewed_at               :datetime
#  revoked_at                :datetime
#  sent_at                   :datetime
#  signed_name_ciphertext    :text
#  status                    :string           default("pending"), not null
#  text_version              :string
#  token_digest              :string
#  verification_note         :text
#  verified_at               :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  recorded_by_id            :bigint
#  reviewed_by_id            :bigint
#  revoked_by_id             :bigint
#  user_id                   :bigint
#  verified_by_id            :bigint
#
# Indexes
#
#  index_guardian_consents_on_recorded_by_id  (recorded_by_id)
#  index_guardian_consents_on_reviewed_by_id  (reviewed_by_id)
#  index_guardian_consents_on_revoked_by_id   (revoked_by_id)
#  index_guardian_consents_on_token_digest    (token_digest) UNIQUE
#  index_guardian_consents_on_user_id         (user_id)
#  index_guardian_consents_on_verified_by_id  (verified_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (recorded_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (reviewed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (revoked_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verified_by_id => users.id) ON DELETE => nullify
#
require "rails_helper"

RSpec.describe GuardianConsent do
  let(:user) { create(:user, :verified, :minor) }

  describe "User#minor?" do
    it "is true under 18 and false from the 18th birthday" do
      travel_to Date.new(2026, 10, 11) do
        expect(build(:user, birthday: Date.new(2008, 10, 12))).to be_minor
        expect(build(:user, birthday: Date.new(2008, 10, 11))).not_to be_minor
      end
    end

    it "is false with no birthday" do
      expect(build(:user, birthday: nil)).not_to be_minor
    end
  end

  describe "User#guardian_consent_missing?" do
    it "is true for a minor until a guardian consents" do
      expect(user.guardian_consent_missing?).to be(true)

      create(:guardian_consent, :granted, user:)

      expect(user.guardian_consent_missing?).to be(false)
    end

    it "ends when the member turns 18" do
      travel_to user.birthday + 18.years do
        expect(user.guardian_consent_missing?).to be(false)
      end
    end

    it "comes back after a revoke" do
      consent = create(:guardian_consent, :granted, user:)
      consent.record_revoke!

      expect(user.guardian_consent_missing?).to be(true)
    end
  end

  describe ".issue!" do
    it "stores only a digest of the token and finds the request by the token" do
      consent = described_class.issue!(user, guardian_name: "Grace Hopper", guardian_email: " Grace@Example.org ")

      expect(consent).to be_persisted
      expect(consent.token_digest).to eq(described_class.digest_for(consent.token))
      expect(consent.guardian_email).to eq("grace@example.org")
      expect(described_class.for_token(consent.token)).to eq(consent)
    end

    it "supersedes the pending request" do
      first = described_class.issue!(user, guardian_name: "Grace Hopper", guardian_email: "grace@example.org")
      second = described_class.issue!(user, guardian_name: "Alan Turing", guardian_email: "alan@example.org")

      expect(first.reload).to be_superseded
      expect(user.current_guardian_consent).to eq(second)
    end

    it "refuses an email address that belongs to a Weave account" do
      other = create(:user, email: "someone@example.org")

      consent = described_class.issue!(user, guardian_name: "Grace Hopper", guardian_email: other.email)

      expect(consent).not_to be_persisted
      expect(consent.errors[:guardian_email].first).to include("belongs to a Weave account")
    end

    it "refuses the member's own address" do
      consent = described_class.issue!(user, guardian_name: "Grace Hopper", guardian_email: user.email)

      expect(consent).not_to be_persisted
    end

    it "keeps the pending request when the new one is not valid" do
      first = described_class.issue!(user, guardian_name: "Grace Hopper", guardian_email: "grace@example.org")
      described_class.issue!(user, guardian_name: "", guardian_email: "")

      expect(first.reload).to be_pending
    end
  end

  describe "#record_grant!" do
    let(:consent) { create(:guardian_consent, user:) }

    it "records who signed, from where, and which text they saw" do
      expect(consent.record_grant!(signed_name: "Grace Hopper", ip: "203.0.113.5", user_agent: "Firefox")).to be(true)

      consent.reload
      expect(consent).to be_granted
      expect(consent.signed_name).to eq("Grace Hopper")
      expect(consent.granted_ip).to eq("203.0.113.5")
      expect(consent.text_version).to eq(described_class::TEXT_VERSION)
    end

    it "does nothing the second time" do
      consent.record_grant!(signed_name: "Grace Hopper", ip: nil, user_agent: nil)

      expect(consent.record_grant!(signed_name: "Someone Else", ip: nil, user_agent: nil)).to be(false)
      expect(consent.reload.signed_name).to eq("Grace Hopper")
    end
  end

  describe "#record_revoke!" do
    it "records who revoked it" do
      admin = create(:user, :superadmin)
      consent = create(:guardian_consent, :granted, user:)

      expect(consent.record_revoke!(by: admin)).to be(true)
      expect(consent.reload).to have_attributes(status: "revoked", revoked_by: admin)
    end

    it "only revokes a granted consent" do
      expect(create(:guardian_consent, user:).record_revoke!).to be(false)
    end
  end

  describe ".record_offline!" do
    it "grants without a link and replaces the request that stood" do
      admin = create(:user, :superadmin)
      pending = create(:guardian_consent, user:)

      consent = described_class.record_offline!(user, guardian_name: "Grace Hopper", guardian_email: "grace@example.org",
                                                      recorded_by: admin, note: "Paper form, filed")

      expect(consent).to be_granted
      expect(consent).to be_offline
      expect(consent.token_digest).to be_nil
      expect(pending.reload).to be_superseded
    end
  end

  it "keeps the guardian's details encrypted" do
    consent = create(:guardian_consent, user:, guardian_email: "grace@example.org")

    raw = described_class.connection.select_one("SELECT guardian_email_ciphertext FROM guardian_consents WHERE id = #{consent.id}")
    expect(raw["guardian_email_ciphertext"]).not_to include("grace")
  end

  describe "retention" do
    it "keeps the consent when the account is deleted, without the user" do
      consent = create(:guardian_consent, :granted, user:)

      user.destroy!

      consent.reload
      expect(consent.user_id).to be_nil
      expect(consent.account_deleted_at).to be_within(1.minute).of(Time.current)
      expect(consent.guardian_email).to be_present
    end

    it "does not find a consent by token after the account is deleted" do
      consent = described_class.issue!(user, guardian_name: "Grace Hopper", guardian_email: "grace@example.org")

      user.destroy!

      expect(described_class.for_token(consent.token)).to be_nil
    end

    it "is purgeable 1 year after the account is deleted" do
      kept = create(:guardian_consent, :granted, account_deleted_at: 11.months.ago)
      old = create(:guardian_consent, :granted, account_deleted_at: 13.months.ago)
      create(:guardian_consent, :granted, granted_at: 3.years.ago)

      expect(described_class.purgeable).to contain_exactly(old)
      expect(described_class.purgeable).not_to include(kept)
    end

    it "is purgeable 30 days after an unanswered link expires" do
      create(:guardian_consent, expires_at: 20.days.ago)
      old = create(:guardian_consent, expires_at: 31.days.ago)

      expect(described_class.purgeable).to contain_exactly(old)
    end

    it "is purgeable 30 days after a newer request replaces it" do
      create(:guardian_consent, status: "superseded", updated_at: 20.days.ago)
      old = create(:guardian_consent, status: "superseded", updated_at: 31.days.ago)

      expect(described_class.purgeable).to contain_exactly(old)
    end
  end
end
