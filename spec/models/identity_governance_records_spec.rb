# frozen_string_literal: true

require "rails_helper"

# The governance log and the NDA records are append-only.
RSpec.describe "Identity governance records", type: :model do
  describe IdentityNda do
    let(:nda) { create(:identity_nda) }

    it "can't change or be deleted" do
      expect { nda.update!(nda_version: "v9") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { nda.destroy! }.to raise_error(IdentityNda::ImmutableError)
      expect(nda.reload.nda_version).to eq("2026-10")
    end

    it "refuses a signing date in the future" do
      expect(build(:identity_nda, signed_on: 1.day.from_now.to_date)).not_to be_valid
    end

    it "has no column for a document" do
      expect(described_class.column_names).to contain_exactly(
        "id", "user_id", "signed_on", "nda_version", "signature_reference", "recorded_by_id", "created_at"
      )
    end

    it "stays when the account is deleted, without the link to it" do
      nda.user.destroy!

      expect(nda.reload.user_id).to be_nil
    end
  end

  describe IdentityGovernanceEvent do
    let(:event) { described_class.record!(:member_removed, actor: create(:user, :owner), subject: create(:user), reason: "Left.") }

    it "can't change or be deleted" do
      expect { event.update!(kind: "approved") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.destroy! }.to raise_error(IdentityGovernanceEvent::ImmutableError)
    end

    it "accepts only known kinds" do
      expect { described_class.record!(:something_else, actor: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "keeps the row when the people are deleted" do
      event.subject.destroy!

      expect(event.reload.subject_id).to be_nil
      expect(event.summary).to include("a deleted user")
    end
  end

  describe IdentityGovernanceProposal do
    it "keeps a PaperTrail history" do
      proposal = create(:identity_governance_proposal)

      proposal.update!(status: "withdrawn")

      expect(proposal.versions.count).to eq(2)
    end
  end
end
