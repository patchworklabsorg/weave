# frozen_string_literal: true

require "rails_helper"

# The governance log is append-only.
RSpec.describe "Identity governance records", type: :model do
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
